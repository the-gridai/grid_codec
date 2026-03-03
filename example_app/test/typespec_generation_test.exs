defmodule ExampleApp.TypespecGenerationTest do
  use ExUnit.Case, async: true

  alias ExampleApp.Events.OrderCreated
  alias ExampleApp.Events.OrderCreatedNoTypespec
  alias ExampleApp.Events.OrderCreatedNoTypespecPlain

  test "example codec exposes generated t/0 and layout/0 types" do
    assert has_type?(OrderCreated, :t, 0)
    assert has_type?(OrderCreated, :layout, 0)
    assert has_type?(OrderCreated, :framed_layout, 0)
  end

  test "types can be referenced from app specs" do
    order = %OrderCreated{
      order_id: <<1::128>>,
      user_id: 42,
      symbol: "BTCUSD",
      side: :buy,
      price: 1000,
      quantity: 1,
      timestamp: 1_700_000_000_000_000,
      flags: 0
    }

    assert is_binary(encode_payload(order))
  end

  test "generate_typespec: false skips generated types" do
    refute has_type?(OrderCreatedNoTypespecPlain, :t, 0)
    refute has_type?(OrderCreatedNoTypespecPlain, :layout, 0)
  end

  test "generate_typespec: false preserves user-defined t/0 and layout/0" do
    assert has_type?(OrderCreatedNoTypespec, :t, 0)
    assert has_type?(OrderCreatedNoTypespec, :layout, 0)

    layout_ast = fetch_type_ast!(OrderCreatedNoTypespec, :layout, 0)
    t_ast = fetch_type_ast!(OrderCreatedNoTypespec, :t, 0)

    assert {:type, _, :tuple, [{:atom, _, :custom_layout}, {:type, _, :binary, []}]} = layout_ast
    assert Macro.to_string(t_ast) =~ "non_neg_integer"
  end

  @spec encode_payload(OrderCreated.t()) :: OrderCreated.layout()
  defp encode_payload(event), do: OrderCreated.encode(event, header: false)

  defp has_type?(module, type_name, arity) do
    case Code.Typespec.fetch_types(module) do
      {:ok, types} ->
        Enum.any?(types, fn
          {:type, {^type_name, _type_ast, args}} -> length(args) == arity
          {_, {^type_name, _type_ast, args}} -> length(args) == arity
          _ -> false
        end)

      :error ->
        false
    end
  end

  defp fetch_type_ast!(module, type_name, arity) do
    case Code.Typespec.fetch_types(module) do
      {:ok, types} ->
        types
        |> Enum.find_value(fn
          {:type, {^type_name, type_ast, args}} when length(args) == arity -> type_ast
          {_, {^type_name, type_ast, args}} when length(args) == arity -> type_ast
          _ -> nil
        end)
        |> case do
          nil -> flunk("Could not find type #{inspect(type_name)}/#{arity} in #{inspect(module)}")
          type_ast -> type_ast
        end

      :error ->
        flunk("Could not fetch types for #{inspect(module)}")
    end
  end
end
