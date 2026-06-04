defmodule R3.ConsumerCodec do
  def validate_all(data) do
    collect_errors(validate_binary(data)) ++ collect_errors(validate_struct(data))
  end

  defp collect_errors(:ok), do: []
  defp collect_errors({:ok, _value}), do: []
  defp collect_errors({:error, %R3.Errors{errors: errors}}), do: errors
  defp collect_errors({:error, error}), do: [error]

  defp validate_binary(data) do
    case data do
      :bin_ok -> :ok
      :bin_err -> {:error, %R3.Errors{errors: [:a]}}
      _ -> {:error, :bin_atom}
    end
  end

  defp validate_struct(data) do
    case data do
      :struct_ok -> {:ok, %{}}
      :struct_err -> {:error, %R3.Errors{errors: [:b]}}
      _ -> {:error, :struct_atom}
    end
  end
end
