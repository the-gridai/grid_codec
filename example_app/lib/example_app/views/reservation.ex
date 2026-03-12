defmodule ExampleApp.Views.Reservation do
  @moduledoc """
  Fixed-size reservation entry used by typed-group and lookup examples.
  """

  use GridCodec.Struct,
    template_id: 301,
    schema_id: 300,
    name: "ExampleApp.Views.Reservation"

  defcodec do
    field :reservation_id, :u64
    field :order_id, :u64
    field :amount, :u64
    field :active, :bool
    field :expires_at, :datetime_us
  end
end
