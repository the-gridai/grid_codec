defmodule ExampleApp.Views.Reservation do
  @moduledoc """
  Fixed-size reservation entry used by typed-group and lookup examples.
  """

  use GridCodec.Struct,
    template_id: 301,
    schema_id: 300,
    name: "ExampleApp.Views.Reservation"

  defcodec do
    field :reservation_id, :u64, doc: "Stable identifier for the reservation."
    field :order_id, :u64, doc: "Order that currently owns the reserved funds."
    field :amount, :u64, doc: "Reserved amount in account units."
    field :active, :bool, doc: "Whether the reservation is still consuming balance."
    field :expires_at, :datetime_us, doc: "Point in time when the reservation should lapse."
  end

  validations do
    validate(compare(:amount, :>, 0, allow_nil?: false),
      name: :positive_amount,
      category: :invariant
    )
  end
end
