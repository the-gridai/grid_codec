defmodule ExampleApp.Views.PlaceReservation do
  @moduledoc """
  Example batch entry for creating a reservation.
  """

  use GridCodec.Struct,
    template_id: 303,
    schema_id: 300,
    name: "ExampleApp.Views.PlaceReservation"

  defcodec do
    field :reservation_id, :u64
    field :amount, :u64
    field :requested_at, :timestamp_us
  end
end
