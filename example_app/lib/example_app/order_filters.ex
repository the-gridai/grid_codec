defmodule ExampleApp.OrderFilters do
  @moduledoc """
  Match predicates for `OrderCreated` event binaries.

  Demonstrates `GridCodec.Match` on business-domain codecs — filtering
  orders by side, flags, and price without decoding the full event.

  ## Usage

      alias ExampleApp.OrderFilters

      {:ok, bin} = OrderCreated.encode(order)

      OrderFilters.buy_order?(bin)          #=> true | false
      OrderFilters.large_buy?(bin)          #=> true | false
      OrderFilters.flagged_order_info(bin)  #=> {:match, map} | :no_match
  """

  use GridCodec.Match

  alias ExampleApp.Events.OrderCreated
  require OrderCreated

  @doc "Returns `true` when the order side is `:buy` (encoded as `0`)."
  defmatch :buy_order?, OrderCreated do
    where(side == 0)
  end

  @doc "Returns `true` when the order side is `:sell` (encoded as `1`)."
  defmatch :sell_order?, OrderCreated do
    where(side == 1)
  end

  @doc "Returns `true` for buy orders with price above 10,000,000 (10M raw units)."
  defmatch :large_buy?, OrderCreated do
    where(side == 0)
    where(price > 10_000_000)
  end

  @doc """
  Returns `{:match, %{order_id: ..., user_id: ..., price: ...}}` for orders
  with any flag bits set, or `:no_match` otherwise.
  """
  defmatch :flagged_order_info, OrderCreated, select: [:order_id, :user_id, :price] do
    where(flags > 0)
  end
end
