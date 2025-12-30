# BEAM Code Analysis for GridCodec
#
# Usage:
#   mix run benchmarks/analyze_beam.exs
#
# This script analyzes the generated BEAM code from codec modules
# to identify optimization opportunities.

defmodule GridCodec.Analysis.SimpleCodec do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
  end
end

defmodule GridCodec.Analysis.WithStrings do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:name, :string16)
  end
end

defmodule BeamAnalyzer do
  @moduledoc """
  Analyzes BEAM bytecode for GridCodec modules.
  """

  def analyze(module) do
    IO.puts("\n#{String.duplicate("=", 60)}")
    IO.puts("Analyzing: #{inspect(module)}")
    IO.puts("#{String.duplicate("=", 60)}\n")

    # Get module info
    info = module.module_info()
    IO.puts("Module attributes:")
    IO.puts("  - Exports: #{length(info[:exports])} functions")

    # Show key functions
    key_fns = [:encode, :decode, :wrap, :get]
    IO.puts("\nKey function arities:")

    for fn_name <- key_fns do
      arities =
        info[:exports]
        |> Enum.filter(fn {name, _} -> name == fn_name end)
        |> Enum.map(fn {_, arity} -> arity end)

      if arities != [] do
        IO.puts("  - #{fn_name}/#{Enum.join(arities, ", ")}")
      end
    end

    # Try to disassemble
    IO.puts("\n--- BEAM Disassembly (encode/1) ---\n")
    disassemble_function(module, :encode, 1)

    IO.puts("\n--- BEAM Disassembly (decode/1) ---\n")
    disassemble_function(module, :decode, 1)

    # Get abstract code if available
    IO.puts("\n--- Generated Code Structure ---\n")
    show_generated_code_info(module)
  end

  defp disassemble_function(module, fun, arity) do
    try do
      # Get the beam file path
      case :code.which(module) do
        :preloaded ->
          IO.puts("(preloaded module - cannot disassemble)")

        path when is_list(path) ->
          path_str = List.to_string(path)

          case :beam_disasm.file(path_str) do
            {:beam_file, _mod, _exports, _attrs, _compile_info, code} ->
              # Find the function
              fn_code =
                Enum.find(code, fn
                  {:function, ^fun, ^arity, _, _} -> true
                  _ -> false
                end)

              case fn_code do
                {:function, _, _, _entry, instructions} ->
                  # Print simplified instruction summary
                  print_instruction_summary(instructions)

                nil ->
                  IO.puts("  Function not found in disassembly")
              end

            {:error, _, reason} ->
              IO.puts("  Disassembly error: #{inspect(reason)}")
          end

        _ ->
          IO.puts("  (in-memory module - cannot disassemble from file)")
          # Try erts_debug for in-memory modules
          try do
            :erts_debug.df(module)
            IO.puts("  Dumped to #{module}.dis")
          rescue
            _ -> IO.puts("  Cannot dump in-memory module")
          end
      end
    rescue
      e ->
        IO.puts("  Error: #{inspect(e)}")
    end
  end

  defp print_instruction_summary(instructions) do
    # Count instruction types
    counts =
      instructions
      |> Enum.map(fn
        {op, _} -> op
        {op, _, _} -> op
        {op, _, _, _} -> op
        {op, _, _, _, _} -> op
        {op, _, _, _, _, _} -> op
        op when is_atom(op) -> op
        _ -> :other
      end)
      |> Enum.frequencies()

    total = Enum.sum(Map.values(counts))
    IO.puts("  Total instructions: #{total}")
    IO.puts("  Instruction breakdown:")

    counts
    |> Enum.sort_by(fn {_, c} -> -c end)
    |> Enum.take(15)
    |> Enum.each(fn {op, count} ->
      pct = Float.round(count / total * 100, 1)
      IO.puts("    #{op}: #{count} (#{pct}%)")
    end)
  end

  defp show_generated_code_info(module) do
    schema = module.__schema__()

    IO.puts("Schema info:")
    IO.puts("  - Fixed fields: #{length(schema.fixed_fields)}")
    IO.puts("  - Var fields: #{length(schema.var_fields)}")
    IO.puts("  - Block length: #{schema.block_length} bytes")

    IO.puts("\nField layout:")

    for {name, type, opts} <- schema.fields do
      presence = Keyword.get(opts, :presence, :optional)
      IO.puts("  - #{name}: #{type} (#{presence})")
    end
  end

  def compare_with_manual do
    IO.puts("\n#{String.duplicate("=", 60)}")
    IO.puts("Comparing GridCodec vs Manual Implementation")
    IO.puts("#{String.duplicate("=", 60)}\n")

    # Manual encode/decode for comparison
    data = %{id: 12345, count: 100, flag: true}

    # GridCodec version
    {gc_time, gc_binary} =
      :timer.tc(fn ->
        for _ <- 1..100_000 do
          GridCodec.Analysis.SimpleCodec.encode(data)
        end
        |> List.last()
      end)

    # Manual version
    {manual_time, manual_binary} =
      :timer.tc(fn ->
        for _ <- 1..100_000 do
          manual_encode(data)
        end
        |> List.last()
      end)

    IO.puts("100,000 iterations:")
    IO.puts("  GridCodec encode: #{gc_time / 1000} ms")
    IO.puts("  Manual encode:    #{manual_time / 1000} ms")
    IO.puts("  Ratio: #{Float.round(gc_time / manual_time, 2)}x")
    IO.puts("\n  Binaries match: #{gc_binary == manual_binary}")

    # Decode comparison
    binary = gc_binary

    {gc_decode_time, _} =
      :timer.tc(fn ->
        for _ <- 1..100_000 do
          GridCodec.Analysis.SimpleCodec.decode(binary)
        end
      end)

    {manual_decode_time, _} =
      :timer.tc(fn ->
        for _ <- 1..100_000 do
          manual_decode(binary)
        end
      end)

    IO.puts("\n  GridCodec decode: #{gc_decode_time / 1000} ms")
    IO.puts("  Manual decode:    #{manual_decode_time / 1000} ms")
    IO.puts("  Ratio: #{Float.round(gc_decode_time / manual_decode_time, 2)}x")
  end

  # Hand-written encode for comparison
  defp manual_encode(%{id: id, count: count, flag: flag}) do
    flag_byte = if flag, do: 1, else: 0
    <<id::little-64, count::little-32, flag_byte::8>>
  end

  # Hand-written decode for comparison
  defp manual_decode(<<id::little-64, count::little-32, flag_byte::8>>) do
    flag =
      case flag_byte do
        0 -> false
        255 -> nil
        _ -> true
      end

    {:ok, %{id: id, count: count, flag: flag}}
  end
end

# Run analysis
BeamAnalyzer.analyze(GridCodec.Analysis.SimpleCodec)
BeamAnalyzer.analyze(GridCodec.Analysis.WithStrings)
BeamAnalyzer.compare_with_manual()
