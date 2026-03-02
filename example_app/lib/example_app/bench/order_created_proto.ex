defmodule ExampleApp.Bench.OrderCreatedProto do
  @moduledoc false
  use Protobuf, syntax: :proto3

  field :order_id, 1, type: :bytes
  field :user_id, 2, type: :uint64
  field :symbol, 3, type: :string
  field :side, 4, type: :uint32
  field :price, 5, type: :uint64
  field :quantity, 6, type: :uint32
  field :timestamp, 7, type: :int64
  field :flags, 8, type: :uint32
end
