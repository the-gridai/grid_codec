defmodule GeneratedUnusedClauseRepro.HandCodec do
  def validate_all(data) do
    errors =
      collect_errors(validate_binary(data)) ++
        collect_errors(validate_struct(data))
    if errors == [], do: :ok, else: {:error, errors}
  end
  defp collect_errors(:ok), do: []
  defp collect_errors({:ok, _value}), do: []
  defp collect_errors({:error, reason}) when is_list(reason), do: reason
  defp collect_errors({:error, reason}), do: [reason]
  defp validate_binary(_data), do: :ok
  defp validate_struct(_data), do: {:ok, %{}}
end
