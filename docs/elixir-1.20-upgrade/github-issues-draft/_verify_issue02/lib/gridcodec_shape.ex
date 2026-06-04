defmodule Verify.GridCodecShape do
  def validate_all(data) do
    __errors_from_validation_result__(validate_binary(data)) ++
      __errors_from_validation_result__(validate_struct(data))
  end

  defp __errors_from_validation_result__(:ok), do: []
  defp __errors_from_validation_result__({:ok, _value}), do: []
  defp __errors_from_validation_result__({:error, %Verify.Errors{errors: errors}}), do: errors
  defp __errors_from_validation_result__({:error, error}), do: [error]

  # OrderCreated-like: binary validation can fail; struct always {:ok, _} or {:error, _}
  defp validate_binary(data) when is_binary(data) do
    with :ok <- :ok do
      :ok
    end
  end
  defp validate_binary(_, _), do: {:error, :invalid_binary}

  defp validate_struct(_data) do
    case :ok do
      :ok -> {:ok, %{}}
      {:error, error} -> {:error, error}
    end
  end
end

defmodule Verify.Errors do
  defstruct [:errors]
end
