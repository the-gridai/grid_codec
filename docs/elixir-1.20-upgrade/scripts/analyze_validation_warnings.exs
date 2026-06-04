# Analyzes generated codec modules for __errors_from_validation_result__/1 warning root cause.
# Run from example_app after compile:
#   cd example_app && mix compile --force 2>&1 | tee /tmp/gc_errors_warnings.log
#   mix run --no-compile ../docs/elixir-1.20-upgrade/scripts/analyze_validation_warnings.exs

defmodule AnalyzeValidationWarnings do
  @app :example_app
  @ebin Path.join([:code.priv_dir(@app) |> Path.dirname(), "ebin"])
           |> then(fn _ ->
             "_build/dev/lib/example_app/ebin"
           end)

  def run do
    warned = warned_modules_from_compile()
    modules = codec_modules_with_errors_helper()

    IO.puts("Codecs with __errors_from_validation_result__/1: #{length(modules)}")
    IO.puts("Modules with compile warning (from last compile log): #{map_size(warned)}")
    IO.puts("")

    rows =
      Enum.map(modules, fn mod ->
        shape = analyze_module(mod)
        Map.put(shape, :warned?, Map.has_key?(warned, mod))
      end)

    print_table(rows)

    IO.puts("\n--- Summary ---")
    warned_rows = Enum.filter(rows, & &1.warned?)
    not_warned = Enum.reject(rows, & &1.warned?)

    IO.puts("Warned: #{length(warned_rows)}")
    IO.puts("Not warned: #{length(not_warned)}")
    if not_warned != [], do: IO.puts("  #{inspect(Enum.map(not_warned, & &1.module))}")

    for key <- [
          :struct_always_ok,
          :binary_collect_always_empty,
          :validate_struct_has_error_branch,
          :errors_helper_call_sites
        ] do
      counts =
        warned_rows
        |> Enum.group_by(&Map.get(&1, key))
        |> Enum.map(fn {k, v} -> {k, length(v)} end)
        |> Enum.sort_by(&elem(&1, 0))

      IO.puts("\nWarned modules by #{key}: #{inspect(counts)}")
    end
  end

  defp codec_modules_with_errors_helper do
    ebin = Path.expand("_build/dev/lib/example_app/ebin", File.cwd!())

    ebin
    |> File.ls!()
    |> Enum.filter(&String.starts_with?(&1, "Elixir.ExampleApp."))
    |> Enum.filter(&String.ends_with?(&1, ".beam"))
    |> Enum.map(fn file ->
      file
      |> String.trim_trailing(".beam")
      |> String.replace_prefix("Elixir.", "")
      |> String.split(".")
      |> Module.concat()
    end)
    |> Enum.filter(fn mod ->
      beam = module_beam_path(mod)
      match?({:ok, _}, read_abstract_code(beam)) and
        find_function(read_abstract_code!(beam), :__errors_from_validation_result__, 1) != nil
    end)
    |> Enum.sort()
  end

  defp read_abstract_code!(beam) do
    {:ok, forms} = read_abstract_code(beam)
    forms
  end

  defp warned_modules_from_compile do
    candidates = [
      "/tmp/gc_errors_warnings.log",
      Path.expand("../example_app_warnings_full.log", __DIR__),
      Path.expand("../../example_app_warnings_full.log", __DIR__)
    ]

    log = Enum.find(candidates, &File.exists?/1)

    if log do
      parse_warning_log(log)
    else
      IO.puts("No warning log found; run: mix compile --force 2>&1 | tee /tmp/gc_errors_warnings.log")
      %{}
    end
  end

  defp parse_warning_log(path) do
    re = ~r/:\s+(.+):__errors_from_validation_result__\/1/

    content = File.read!(path)

    Regex.scan(re, content)
    |> List.flatten()
    |> Enum.map(fn mod_str ->
      mod_str
      |> String.split(".")
      |> Module.concat()
    end)
    |> Map.new(&{&1, true})
  end

  defp analyze_module(mod) do
    beam = module_beam_path(mod)

    case read_abstract_code(beam) do
      {:ok, forms} ->
        %{
          module: mod,
          struct_always_ok: validate_struct_always_ok?(forms),
          validate_struct_has_error_branch: validate_struct_has_error_branch?(forms),
          binary_collect_always_empty: binary_collect_always_empty?(forms),
          validate_binary_can_error: validate_binary_can_error?(forms),
          errors_helper_call_sites: count_errors_helper_calls(forms),
          errors_helper_clauses: errors_helper_clause_count(forms)
        }

      {:error, reason} ->
        %{
          module: mod,
          error: reason
        }
    end
  end

  defp module_beam_path(mod) do
    ebin = Path.expand("_build/dev/lib/example_app/ebin", File.cwd!())
    Path.join(ebin, "Elixir.#{inspect(mod)}.beam")
  end

  defp read_abstract_code(beam) do
  case :beam_lib.chunks(String.to_charlist(beam), [:abstract_code]) do
      {:ok, {_, [{:abstract_code, {_, forms}} | _]}} -> {:ok, forms}
      {:ok, {_, _}} -> {:error, :no_abstract_code}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_struct_always_ok?(forms) do
    case find_function(forms, :validate_struct, 1) do
      nil ->
        nil

      {:function, _, _, _, clauses} ->
        Enum.all?(clauses, fn
          {:clause, _, _, [], [{:tuple, _, [{:atom, _, :ok}, _]}]} -> true
          _ -> false
        end)
    end
  end

  defp validate_struct_has_error_branch?(forms) do
    case find_function(forms, :validate_struct, 1) do
      nil ->
        false

      {:function, _, _, _, clauses} ->
        Enum.any?(clauses, fn {:clause, _, _, [], body} ->
          body_has_error_tuple?(body)
        end)
    end
  end

  defp body_has_error_tuple?(body) do
    Enum.any?(body, fn
      {:tuple, _, [{:atom, _, :error}, _]} -> true
      {:case, _, _, _} -> true
      {:if, _, _, _} -> true
      _ -> false
    end)
  end

  defp binary_collect_always_empty?(forms) do
    case find_function(forms, :__collect_binary_validation_errors__, 2) do
      nil ->
        nil

      {:function, _, _, _, clauses} ->
        Enum.all?(clauses, fn
          {:clause, _, _, [], [{nil, _, []}]} -> true
          {:clause, _, _, [], [body]} -> empty_list_body?(body)
          _ -> false
        end)
    end
  end

  defp empty_list_body?([{:nil, _, []}]), do: true
  defp empty_list_body?(_), do: false

  defp validate_binary_can_error?(forms) do
    case find_function(forms, :validate_binary, 2) do
      nil ->
        nil

      {:function, _, _, _, clauses} ->
        Enum.any?(clauses, fn {:clause, _, _, _, body} ->
          body_has_with_else_error?(body) or body_has_error_tuple?(body)
        end)
    end
  end

  defp body_has_with_else_error?(body) do
    Enum.any?(body, fn
      {:case, _, {:call, _, {:atom, _, :__validation_error_result__}, _}, _} -> true
      {:case, _, {:call, _, {:atom, _, :__prepare_validation_binary__}, _}, _} -> true
      _ -> false
    end)
  end

  defp count_errors_helper_calls(forms) do
    forms
    |> Enum.flat_map(&collect_calls_in_form/1)
    |> Enum.count(&(&1 == :__errors_from_validation_result__))
  end

  defp collect_calls_in_form({:function, _, _name, _arity, clauses}) do
    Enum.flat_map(clauses, fn {:clause, _, _, _, body} -> Enum.flat_map(body, &calls_in_expr/1) end)
  end

  defp collect_calls_in_form(_), do: []

  defp calls_in_expr({:call, _, {:atom, _, name}, _args}), do: [name]
  defp calls_in_expr(ast) when is_tuple(ast), do: ast |> Tuple.to_list() |> Enum.flat_map(&calls_in_expr/1)
  defp calls_in_expr(_), do: []

  defp errors_helper_clause_count(forms) do
    case find_function(forms, :__errors_from_validation_result__, 1) do
      {:function, _, _, _, clauses} -> length(clauses)
      _ -> 0
    end
  end

  defp find_function(forms, name, arity) do
    Enum.find(forms, fn
      {:function, _, ^name, ^arity, _} -> true
      _ -> false
    end)
  end

  defp print_table(rows) do
    header = [
      "warned?",
      "module",
      "struct_ok_only",
      "struct_err_branch",
      "bin_collect_empty",
      "bin_can_error",
      "err_calls",
      "clauses"
    ]

    IO.puts(Enum.join(header, "\t"))

    for r <- rows do
      if Map.has_key?(r, :error) do
        IO.puts("?\t#{r.module}\tERROR #{inspect(r.error)}")
      else
        IO.puts([
          if(r.warned?, do: "Y", else: "n"),
          "\t",
          Atom.to_string(r.module) |> String.replace("Elixir.", ""),
          "\t",
          to_string(r.struct_always_ok),
          "\t",
          to_string(r.validate_struct_has_error_branch),
          "\t",
          to_string(r.binary_collect_always_empty),
          "\t",
          to_string(r.validate_binary_can_error),
          "\t",
          to_string(r.errors_helper_call_sites),
          "\t",
          to_string(r.errors_helper_clauses)
        ])
      end
    end
  end
end

AnalyzeValidationWarnings.run()
