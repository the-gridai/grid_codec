defmodule Full.ConsumerCodec do
  def validate_all(data) do
    collect_errors(validate_binary(data)) ++ collect_errors(validate_struct(data))
  end

  defp collect_errors(:ok), do: []
  defp collect_errors({:ok, _value}), do: []
  defp collect_errors({:error, reason}) when is_list(reason), do: reason
  defp collect_errors({:error, reason}), do: [reason]

  defp validate_binary(_), do: {:error, [:bin_err]}
  defp validate_struct(_), do: {:error, :struct_err}
end
