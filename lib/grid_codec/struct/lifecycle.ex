defmodule GridCodec.Struct.Lifecycle do
  @moduledoc false

  @spec normalize_before_encode(module(), term()) :: {:ok, struct()} | {:error, term()}
  def normalize_before_encode(module, result) when is_atom(module) do
    normalize_hook_result(module, :before_encode, result)
  end

  @spec normalize_after_decode(module(), term()) :: {:ok, struct()} | {:error, term()}
  def normalize_after_decode(module, result) when is_atom(module) do
    normalize_hook_result(module, :after_decode, result)
  end

  defp normalize_hook_result(module, _hook, %{__struct__: struct_module} = struct)
       when struct_module == module do
    {:ok, struct}
  end

  defp normalize_hook_result(module, _hook, {:ok, %{__struct__: struct_module} = struct})
       when struct_module == module do
    {:ok, struct}
  end

  defp normalize_hook_result(_module, _hook, {:error, _reason} = error), do: error

  defp normalize_hook_result(_module, hook, other) do
    {:error, {:"invalid_#{hook}_return", other}}
  end
end
