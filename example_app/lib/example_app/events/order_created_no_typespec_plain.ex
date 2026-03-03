defmodule ExampleApp.Events.OrderCreatedNoTypespecPlain do
  @moduledoc """
  Example codec with typespec generation disabled and no custom types.
  """
  use GridCodec.Struct,
    template_id: 998,
    schema_id: 100,
    name: "OrderCreatedNoTypespecPlain",
    generate_typespec: false

  defcodec do
    field :order_id, :uuid
    field :price, :u64
  end
end
