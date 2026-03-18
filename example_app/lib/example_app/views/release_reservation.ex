defmodule ExampleApp.Views.ReleaseReservation do
  @moduledoc """
  Example batch entry for releasing a reservation.
  """

  use GridCodec.Struct,
    template_id: 304,
    schema_id: 300,
    name: "ExampleApp.Views.ReleaseReservation"

  defcodec do
    field :reservation_id, :u64, doc: "Reservation that should be released."
    field :reason_code, :u8, doc: "Compact reason code for the release operation."
    field :released_at, :timestamp_us, doc: "Timestamp when the release was recorded."
  end
end
