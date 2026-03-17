defmodule GridCodec.ValidationError do
  @moduledoc """
  Raised when a field value or invariant doesn't match the expected GridCodec rules.

  Provides structured, matchable error information:

  - `code` — atom for pattern matching (`:type_mismatch`, `:out_of_range`,
    `:invalid_format`, `:cast_error`, `:required_field`, `:invariant_failed`)
  - `details` — field name, expected type, actual value, module, and description
  - `message` — generated lazily from details when accessed (via `Exception.message/1`)

  ## Pattern Matching

      try do
        MyCodec.encode(data)
      rescue
        %GridCodec.ValidationError{code: :out_of_range, details: %{field: :price}} = e ->
          Logger.error(Exception.message(e))
          {:error, e}
      end
  """

  defexception [:code, :details]

  @type t :: %__MODULE__{
          code:
            :type_mismatch
            | :out_of_range
            | :invalid_format
            | :cast_error
            | :required_field
            | :invariant_failed,
          details: %{
            optional(:field) => atom(),
            optional(:type) => atom() | module(),
            optional(:value) => term(),
            optional(:name) => atom(),
            optional(:category) => atom(),
            optional(:metadata) => map(),
            required(:module) => module(),
            required(:description) => String.t()
          }
        }

  @impl true
  def message(%__MODULE__{
        code: code,
        details: %{field: field, type: type, value: value, module: module, description: desc}
      }) do
    "Field #{inspect(field)} in #{inspect(module)} — #{format_code(code)} for #{inspect(type)}. #{desc}, got #{inspect(value)}."
  end

  def message(%__MODULE__{
        code: code,
        details: %{field: field, module: module, description: desc}
      }) do
    "Field #{inspect(field)} in #{inspect(module)} — #{format_code(code)}. #{desc}."
  end

  def message(%__MODULE__{
        code: code,
        details: %{name: name, module: module, description: desc}
      }) do
    "Validation #{inspect(name)} in #{inspect(module)} — #{format_code(code)}. #{desc}."
  end

  def message(%__MODULE__{
        code: code,
        details: %{module: module, description: desc}
      }) do
    "#{inspect(module)} — #{format_code(code)}. #{desc}."
  end

  defp format_code(:out_of_range), do: "out of range"
  defp format_code(:type_mismatch), do: "type mismatch"
  defp format_code(:invalid_format), do: "invalid format"
  defp format_code(:cast_error), do: "cannot cast"
  defp format_code(:required_field), do: "required field missing"
  defp format_code(:invariant_failed), do: "invariant failed"

  @doc false
  def cast_error(module, field, type, value, reason) do
    %__MODULE__{
      code: :cast_error,
      details: %{field: field, type: type, value: value, module: module, description: reason}
    }
  end

  @doc false
  def out_of_range(module, field, type, value, range_desc) do
    %__MODULE__{
      code: :out_of_range,
      details: %{
        field: field,
        type: type,
        value: value,
        module: module,
        description: "Expected #{range_desc}"
      }
    }
  end

  @doc false
  def type_mismatch(module, field, type, value, expected_desc) do
    %__MODULE__{
      code: :type_mismatch,
      details: %{
        field: field,
        type: type,
        value: value,
        module: module,
        description: "Expected #{expected_desc}"
      }
    }
  end

  @doc false
  def field_from_argument_error(message) when is_binary(message) do
    case Regex.run(~r/field :([\w]+)/, message) do
      [_, field_str] -> String.to_atom(field_str)
      _ -> :unknown
    end
  end

  @doc false
  def invalid_format(module, field, type, value, format_desc) do
    %__MODULE__{
      code: :invalid_format,
      details: %{
        field: field,
        type: type,
        value: value,
        module: module,
        description: "Expected #{format_desc}"
      }
    }
  end

  @doc false
  def required_field(module, field) do
    %__MODULE__{
      code: :required_field,
      details: %{
        field: field,
        module: module,
        description: "required field #{inspect(field)} cannot be nil"
      }
    }
  end

  @doc false
  def invariant_failed(module, name, description, metadata \\ %{}) do
    %__MODULE__{
      code: :invariant_failed,
      details: %{
        module: module,
        name: name,
        description: description,
        metadata: metadata
      }
    }
  end
end
