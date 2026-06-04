defmodule Bisect.Codec do
  def run(data) do
    collect_errors(validate_binary(data)) ++ collect_errors(validate_struct(data))
  end
  defp collect_errors(:ok), do: []
  defp collect_errors({:ok, _value}), do: []
  defp collect_errors({:error, reason}) when is_list(reason), do: reason
  defp collect_errors({:error, reason}), do: [reason]
  defp validate_binary(_data), do: :ok
  defp validate_struct(_data), do: {:ok, %{}}
end
