defmodule UnusedValidationErrorClausesRepro.Codec do
  @moduledoc false
  defstruct [:amount]

  # Same shape as GridCodec decode(validate: :both) after a successful decode.
  def validate_both(%__MODULE__{} = struct, binary) when is_binary(binary) do
    errors =
      __errors_from_validation_result__(validate_binary(binary)) ++
        __errors_from_validation_result__(validate_struct(struct))

    if errors == [], do: :ok, else: {:error, errors}
  end

  # --- Normalizer (four heads, same as GridCodec compiler) ---
  defp __errors_from_validation_result__(:ok), do: []
  defp __errors_from_validation_result__({:ok, _value}), do: []

  defp __errors_from_validation_result__(
         {:error, %UnusedValidationErrorClausesRepro.ValidationErrors{errors: errors}}
       ),
       do: errors

  defp __errors_from_validation_result__({:error, error}), do: [error]

  # validation_active: false → only success (GridCodec default for most codecs)
  def validate_struct(%__MODULE__{} = struct), do: {:ok, struct}

  # binary_checks == [] → collector always empty
  defp __collect_binary_validation_errors__(_binary, _header?), do: []

  defp __validation_error_result__([]), do: :ok
  defp __validation_error_result__([error]), do: {:error, error}

  defp __validation_error_result__(errors) do
    {:error, %UnusedValidationErrorClausesRepro.ValidationErrors{errors: errors}}
  end

  defp __prepare_validation_binary__(binary, _header?), do: {:ok, binary}

  def validate_binary(binary, opts \\ [])

  def validate_binary(binary, opts) when is_binary(binary) do
    header? = Keyword.get(opts, :header, true)

    with {:ok, prepared} <- __prepare_validation_binary__(binary, header?),
         :ok <-
           __validation_error_result__(
             __collect_binary_validation_errors__(prepared, header?)
           ) do
      :ok
    end
  end

  def validate_binary(_, _), do: {:error, :invalid_binary}
end

# Counterexample (uncomment to verify warnings go away):
#
# Replace validate_struct/1 above with:
#
#   def validate_struct(%__MODULE__{} = struct) do
#     case __validate__(struct) do
#       :ok -> {:ok, struct}
#       {:error, error} -> {:error, error}
#     end
#   end
#
#   defp __validate__(%{amount: n}) when n > 0, do: :ok
#   defp __validate__(_), do: {:error, :invalid}
