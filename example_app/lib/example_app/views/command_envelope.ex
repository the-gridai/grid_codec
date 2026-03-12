defmodule ExampleApp.Views.CommandEnvelope do
  @moduledoc """
  Example heterogeneous batch with a generated keyed lookup.
  """

  use GridCodec.Struct,
    template_id: 305,
    schema_id: 300,
    name: "ExampleApp.Views.CommandEnvelope"

  alias ExampleApp.Views.{PlaceReservation, ReleaseReservation}

  defcodec do
    field :account_id, :u64

    batch :commands, any_of: [PlaceReservation, ReleaseReservation]

    lookups do
      lookup :commands_by_reservation_id do
        from(:commands)
        into(:map)
        key(PlaceReservation, :reservation_id)
        key(ReleaseReservation, :reservation_id)
      end
    end
  end
end
