defmodule ExampleApp.Views.PlaceReservation do
  @moduledoc """
  Example batch entry for creating a reservation.
  """

  use GridCodec.Struct,
    template_id: 303,
    schema_id: 300,
    name: "ExampleApp.Views.PlaceReservation"

  defcodec do
    field :reservation_id, :u64, doc: "Reservation to create or refresh."
    field :amount, :u64, doc: "Amount that should be reserved."
    field :requested_at, :timestamp_us, doc: "Timestamp when the reservation was requested."
  end
end
