defmodule Single.ConsumerCodec do
  def only_binary(data), do: collect_errors(validate_binary(data))
  def only_struct(data), do: collect_errors(validate_struct(data))

  defp collect_errors(:ok), do: []
  defp collect_errors({:ok, _value}), do: []
  defp collect_errors({:error, reason}) when is_list(reason), do: reason
  defp collect_errors({:error, reason}), do: [reason]

  defp validate_binary(_), do: :ok
  defp validate_struct(_), do: {:ok, %{}}
end
