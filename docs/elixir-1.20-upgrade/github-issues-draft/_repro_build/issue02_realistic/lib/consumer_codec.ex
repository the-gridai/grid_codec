defmodule Realistic.ConsumerCodec do
  @spec validate_all(term()) :: :ok | {:error, list()}
  def validate_all(data) do
    errors =
      collect_errors(validate_binary(data)) ++
        collect_errors(validate_struct(data))

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp collect_errors(:ok), do: []
  defp collect_errors({:ok, _value}), do: []
  defp collect_errors({:error, %Errors{errors: errors}}), do: errors
  defp collect_errors({:error, error}), do: [error]

  @spec validate_binary(term()) :: :ok | {:error, term()}
  defp validate_binary(_), do: :ok

  @spec validate_struct(term()) :: {:ok, map()} | {:error, term()}
  defp validate_struct(_), do: {:ok, %{}}
end

defmodule Errors do
  defstruct [:errors]
end
