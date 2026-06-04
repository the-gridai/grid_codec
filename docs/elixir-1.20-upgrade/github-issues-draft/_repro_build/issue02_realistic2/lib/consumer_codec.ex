defmodule R2.ConsumerCodec do
  def validate_all(data) do
    collect_errors(validate_binary(data)) ++ collect_errors(validate_struct(data))
  end

  defp collect_errors(:ok), do: []
  defp collect_errors({:ok, _value}), do: []
  defp collect_errors({:error, %Errors{errors: errors}}), do: errors
  defp collect_errors({:error, error}), do: [error]

  defp validate_binary(data) do
    if is_binary(data), do: :ok, else: {:error, :bad}
  end

  defp validate_struct(data) do
    if is_map(data), do: {:ok, data}, else: {:error, :bad}
  end
end

defmodule Errors do
  defstruct [:errors]
end
