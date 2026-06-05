defmodule GridCodec.DocExampleValues do
  @moduledoc false

  # Deterministic literals for compiler-emitted `iex>` doctests on codec modules.
  #
  # ## Return contract for `doc_section_* /N`
  #
  # Each function returns either:
  #
  #   * `{:iex_examples, markdown}` — a `## Examples` section containing `iex>` / result
  #     lines that ExUnit `doctest/1` can run.
  #
  #   * `:no_iex_examples` — we cannot synthesize a stable runnable example from the
  #     given `doc_ctx` or options. The compiler then decides what to show:
  #     - `new/1`: static prose (still no `iex>`).
  #     - `new_binary/1`: static indented samples without `iex>` (when attrs unknown).
  #     - `encode/2`, `decode/2`, `validate_struct/1`: omit an extra Examples block
  #       (those docs are already mostly prose + options).

  @doc false
  @spec build([tuple()], [tuple()], list()) :: {:ok, map()} | :skip
  def build(_resolved_fields, _processed_groups, batches) when batches != [],
    do: :skip

  def build(resolved_fields, processed_groups, []) do
    with {:ok, field_frags} <- field_fragments(resolved_fields),
         {:ok, group_frags} <- group_fragments(processed_groups) do
      attrs = Enum.join(field_frags ++ group_frags, ", ")
      cast = cast_sandbox_field(resolved_fields)
      {:ok, %{attrs: attrs, cast_field: cast}}
    else
      :skip -> :skip
    end
  end

  defp field_fragments(resolved_fields) do
    resolved_fields
    |> Enum.reduce_while({:ok, []}, fn field, {:ok, acc} ->
      case field_fragment(field) do
        {:ok, frag} -> {:cont, {:ok, [frag | acc]}}
        :skip -> {:halt, :skip}
      end
    end)
    |> case do
      {:ok, frags} -> {:ok, Enum.reverse(frags)}
      :skip -> :skip
    end
  end

  defp field_fragment({name, _type_atom, _module, opts} = field) do
    if Keyword.get(opts, :presence) == :constant do
      const = Keyword.fetch!(opts, :value)
      {:ok, "#{name}: #{inspect(const)}"}
    else
      case value_source(field) do
        {:ok, src} -> {:ok, "#{name}: #{src}"}
        :skip -> :skip
      end
    end
  end

  defp group_fragments(processed_groups) do
    processed_groups
    |> Enum.reduce_while({:ok, []}, fn {gname, _block, opts}, {:ok, acc} ->
      if Keyword.get(opts, :is_batch, false) do
        {:halt, :skip}
      else
        {:cont, {:ok, ["#{gname}: []" | acc]}}
      end
    end)
    |> case do
      {:ok, frags} -> {:ok, Enum.reverse(frags)}
      :skip -> :skip
    end
  end

  defp value_source({_name, _type_atom, type_module, opts} = field) do
    domain = type_module
    wire = Keyword.get(opts, :__wire_module__, domain)

    cond do
      function_exported?(domain, :doc_example_source, 0) ->
        {:ok, domain.doc_example_source()}

      function_exported?(domain, :from_uuid, 1) and match?("Elixir." <> _, Atom.to_string(domain)) ->
        {:ok, "#{inspect(domain)}.from_uuid(\"00000000-0000-4000-8000-000000000001\")"}

      enum_like?(domain) ->
        case first_enum_atom(domain) do
          nil -> :skip
          atom -> {:ok, inspect(atom)}
        end

      domain == GridCodec.Types.Bitset or bitset_impl?(domain) ->
        {:ok, "MapSet.new([])"}

      domain == GridCodec.Types.CharArray or char_array_impl?(domain) ->
        char_array_example(domain)

      true ->
        scalar_or_domain(domain, wire, field)
    end
  end

  defp bitset_impl?(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :to_integer, 1) and
      function_exported?(mod, :from_integer, 1) and !enum_like?(mod)
  end

  defp char_array_impl?(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :__char_array_meta__, 0)
  end

  defp char_array_example(mod) do
    %{length: len} = mod.__char_array_meta__()
    {:ok, inspect(String.duplicate("A", len))}
  rescue
    _ -> :skip
  end

  defp enum_like?(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :values, 0) and
      function_exported?(mod, :to_integer, 1)
  end

  defp first_enum_atom(mod) do
    mod.values()
    |> List.first()
    |> case do
      {atom, _int} when is_atom(atom) -> atom
      _ -> nil
    end
  end

  defp scalar_or_domain(domain, wire, {_name, type_atom, _dm, opts}) do
    type_opts = Keyword.get(opts, :__type_opts__, [])

    case domain do
      GridCodec.Types.UUID ->
        {:ok, "<<1::128>>"}

      GridCodec.Types.UUIDString ->
        {:ok, ~s("00000000-0000-4000-8000-000000000001")}

      GridCodec.Types.Bool ->
        {:ok, "true"}

      GridCodec.Types.String ->
        {:ok, ~s("hi")}

      GridCodec.Types.String8 ->
        {:ok, ~s("hi")}

      GridCodec.Types.String16 ->
        {:ok, ~s("hi")}

      GridCodec.Types.String32 ->
        {:ok, ~s("hi")}

      GridCodec.Types.TimestampMicros ->
        {:ok, "1_700_000_000_000_000"}

      GridCodec.Types.TimestampNanos ->
        {:ok, "1_700_000_000_000_000_000"}

      GridCodec.Types.DateTimeMicros ->
        {:ok, "~U[2024-01-01 00:00:00.000000Z]"}

      GridCodec.Types.DateTimeNanos ->
        {:ok, "~U[2024-01-01 00:00:00.000000000Z]"}

      GridCodec.Types.Decimal ->
        {:ok, "Decimal.new(\"1.00\")"}

      GridCodec.Types.PositiveDecimal ->
        {:ok, "Decimal.new(\"1.00\")"}

      GridCodec.Types.F32 ->
        {:ok, "1.0"}

      GridCodec.Types.F64 ->
        {:ok, "1.0"}

      _ ->
        cond do
          domain in [
            GridCodec.Types.I8,
            GridCodec.Types.I16,
            GridCodec.Types.I32,
            GridCodec.Types.I64
          ] ->
            {:ok, "1"}

          domain in [
            GridCodec.Types.U8,
            GridCodec.Types.U16,
            GridCodec.Types.U32,
            GridCodec.Types.U64
          ] ->
            {:ok, "1"}

          wire_format_integer?(wire) ->
            {:ok, "1"}

          match?({:ok, _}, GridCodec.Type.lookup(type_atom)) ->
            # Parameterized / unknown composite at this field's declared atom
            parameterized_domain(domain, type_opts)

          true ->
            :skip
        end
    end
  end

  defp wire_format_integer?(wire) do
    wire in [
      GridCodec.Types.U8,
      GridCodec.Types.U16,
      GridCodec.Types.U32,
      GridCodec.Types.U64,
      GridCodec.Types.I8,
      GridCodec.Types.I16,
      GridCodec.Types.I32,
      GridCodec.Types.I64
    ]
  end

  defp parameterized_domain(GridCodec.Types.Decimal, _opts), do: {:ok, "Decimal.new(\"1.00\")"}

  defp parameterized_domain(GridCodec.Types.PositiveDecimal, _opts),
    do: {:ok, "Decimal.new(\"1.00\")"}

  defp parameterized_domain(_, _), do: :skip

  defp cast_sandbox_field(resolved_fields) do
    Enum.find_value(resolved_fields, fn {name, _ta, mod, opts} ->
      wire = Keyword.get(opts, :__wire_module__, mod)

      if wire in [
           GridCodec.Types.U8,
           GridCodec.Types.U16,
           GridCodec.Types.U32,
           GridCodec.Types.U64
         ],
         do: name,
         else: nil
    end)
  end

  @doc false
  def doc_section_new(module, doc_ctx, _validation_active)

  def doc_section_new(_module, :disabled, _), do: :no_iex_examples
  def doc_section_new(_module, :skip, _), do: :no_iex_examples

  def doc_section_new(module, {:ok, ctx}, _validation_active) do
    attrs = ctx.attrs
    cast = ctx.cast_field

    lines =
      [
        "iex> {:ok, s} = #{inspect(module)}.new([#{attrs}])",
        "iex> s.__struct__ == #{inspect(module)}",
        "true"
      ] ++
        if(cast,
          do: [
            "iex> match?({:error, _}, #{inspect(module)}.new(Keyword.put([#{attrs}], :#{cast}, \"not_a_number\")))",
            "true"
          ],
          else: []
        )

    {:iex_examples, "      ## Examples\n\n          " <> Enum.join(lines, "\n          ")}
  end

  @doc false
  def doc_section_new_binary(module, {:ok, %{attrs: attrs}}, _) do
    lines = [
      "iex> {:ok, bin} = #{inspect(module)}.new_binary([#{attrs}])",
      "iex> is_binary(bin)",
      "true"
    ]

    {:iex_examples, "      ## Examples\n\n          " <> Enum.join(lines, "\n          ")}
  end

  def doc_section_new_binary(_, _, _), do: :no_iex_examples

  @doc false
  def doc_section_encode(module, {:ok, %{attrs: attrs}}, _) do
    lines = [
      "iex> {:ok, s} = #{inspect(module)}.new([#{attrs}])",
      "iex> {:ok, bin} = #{inspect(module)}.encode(s)",
      "iex> match?({:ok, _}, #{inspect(module)}.decode(bin))",
      "true"
    ]

    {:iex_examples, "      ## Examples\n\n          " <> Enum.join(lines, "\n          ")}
  end

  def doc_section_encode(_, _, _), do: :no_iex_examples

  @doc false
  def doc_section_decode(module, {:ok, %{attrs: attrs}}, _) do
    lines = [
      "iex> {:ok, s} = #{inspect(module)}.new([#{attrs}])",
      "iex> {:ok, bin} = #{inspect(module)}.encode(s)",
      "iex> match?({:ok, _}, #{inspect(module)}.decode(bin))",
      "true"
    ]

    {:iex_examples, "      ## Examples\n\n          " <> Enum.join(lines, "\n          ")}
  end

  def doc_section_decode(_, _, _), do: :no_iex_examples

  @doc false
  def doc_section_validate_struct(module, {:ok, %{attrs: attrs}}, true) do
    lines = [
      "iex> {:ok, s} = #{inspect(module)}.new([#{attrs}])",
      "iex> match?({:ok, _}, #{inspect(module)}.validate_struct(s))",
      "true"
    ]

    {:iex_examples, "      ## Examples\n\n          " <> Enum.join(lines, "\n          ")}
  end

  def doc_section_validate_struct(_, _, _), do: :no_iex_examples
end
