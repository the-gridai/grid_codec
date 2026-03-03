defmodule ExampleApp.Events.OrderCreatedNoTypespec do
  @moduledoc """
  Example codec with typespec generation disabled.
  """
  use GridCodec.Struct,
    template_id: 999,
    schema_id: 100,
    name: "OrderCreatedNoTypespec",
    generate_typespec: false

  @type t() :: %__MODULE__{
          order_id: binary() | nil,
          price: non_neg_integer() | nil
        }

  @type layout() :: {:custom_layout, binary()}

  defcodec do
    field :order_id, :uuid
    field :price, :u64
  end
end
