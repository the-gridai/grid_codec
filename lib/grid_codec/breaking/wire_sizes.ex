defmodule GridCodec.Breaking.WireSizes do
  @moduledoc """
  Maps built-in GridCodec type atoms to their fixed wire sizes in bytes.

  Returns `:variable` for variable-length types (strings) and `:unknown`
  for custom/composite types that require schema-level resolution.
  """

  @fixed_sizes %{
    u8: 1,
    u16: 2,
    u32: 4,
    u64: 8,
    i8: 1,
    i16: 2,
    i32: 4,
    i64: 8,
    f32: 4,
    f64: 8,
    bool: 1,
    uuid: 16,
    uuid_string: 16,
    decimal: 9,
    positive_decimal: 9,
    timestamp_us: 8,
    timestamp_ns: 8,
    datetime_us: 8,
    datetime_ns: 8
  }

  @variable_types [:string, :string8, :string16, :string32]

  @doc """
  Returns the wire size for a built-in type atom.

  - Fixed types return an integer (bytes)
  - Variable-length types return `:variable`
  - Unknown/custom types return `:unknown`
  """
  @spec wire_size(atom()) :: pos_integer() | :variable | :unknown
  def wire_size(type) when is_map_key(@fixed_sizes, type), do: Map.fetch!(@fixed_sizes, type)
  def wire_size(type) when type in @variable_types, do: :variable
  def wire_size(_type), do: :unknown

  @doc "Returns true if the type is a known built-in type."
  @spec known?(atom()) :: boolean()
  def known?(type), do: type in Map.keys(@fixed_sizes) or type in @variable_types

  @doc """
  Resolves wire size for a type, falling back to composite type resolution.

  Composite types (defined with `type` blocks in `.grid`) have their size
  computed by summing their field sizes.
  """
  @spec resolve(atom(), map()) :: pos_integer() | :variable | :unknown
  def resolve(type, schema_types) do
    case wire_size(type) do
      :unknown ->
        case Map.get(schema_types, type) do
          %{kind: :prefixed_id} ->
            17

          %{kind: :char_array, params: %{length: n}} when is_integer(n) ->
            n

          %{kind: :bitset, underlying_type: ut} when is_atom(ut) ->
            wire_size(ut)

          %{fields: fields} ->
            sizes = Enum.map(fields, fn f -> wire_size(f.type) end)

            if Enum.all?(sizes, &is_integer/1) do
              Enum.sum(sizes)
            else
              :unknown
            end

          nil ->
            :unknown
        end

      size ->
        size
    end
  end
end
