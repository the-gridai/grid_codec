defmodule GridCodec.ValidationError do
  @moduledoc """
  Raised when a field value doesn't match the expected GridCodec type.

  Provides structured, matchable error information:

  - `code` — atom for pattern matching (`:type_mismatch`, `:out_of_range`, `:invalid_format`)
  - `message` — human-readable explanation
  - `details` — field name, expected type, actual value, and module

  ## Pattern Matching

      try do
        MyCodec.encode(data)
      rescue
        %GridCodec.ValidationError{code: :out_of_range} = e ->
          Logger.error(Exception.message(e))
          {:error, e}
      end

  ## Example Messages

      ** (GridCodec.ValidationError) Field :price in MyCodec — out of range for :u32.
      Expected 0..4294967295, got 5000000000.

      ** (GridCodec.ValidationError) Field :side in MyCodec — type mismatch for OrderSide.
      Expected one of [:buy, :sell] or nil, got :hold.

      ** (GridCodec.ValidationError) Field :id in MyCodec — invalid format for :uuid.
      Expected 16-byte binary or 36-char UUID string, got "not-a-uuid".
  """

  defexception [:code, :message, :details]

  @type t :: %__MODULE__{
          code: :type_mismatch | :out_of_range | :invalid_format,
          message: String.t(),
          details: %{
            field: atom(),
            type: atom() | module(),
            value: term(),
            module: module()
          }
        }

  @doc false
  def out_of_range(module, field, type, value, range_desc) do
    %__MODULE__{
      code: :out_of_range,
      message:
        "Field #{inspect(field)} in #{inspect(module)} — out of range for #{inspect(type)}. " <>
          "Expected #{range_desc}, got #{inspect(value)}.",
      details: %{field: field, type: type, value: value, module: module}
    }
  end

  @doc false
  def type_mismatch(module, field, type, value, expected_desc) do
    %__MODULE__{
      code: :type_mismatch,
      message:
        "Field #{inspect(field)} in #{inspect(module)} — type mismatch for #{inspect(type)}. " <>
          "Expected #{expected_desc}, got #{inspect(value)}.",
      details: %{field: field, type: type, value: value, module: module}
    }
  end

  @doc false
  def invalid_format(module, field, type, value, format_desc) do
    %__MODULE__{
      code: :invalid_format,
      message:
        "Field #{inspect(field)} in #{inspect(module)} — invalid format for #{inspect(type)}. " <>
          "Expected #{format_desc}, got #{inspect(value)}.",
      details: %{field: field, type: type, value: value, module: module}
    }
  end
end
