defmodule ExampleApp.Views.CurrencyAccount do
  @moduledoc """
  Example aggregate-style codec using typed groups and generated lookups.
  """

  use GridCodec.Struct,
    template_id: 302,
    schema_id: 300,
    name: "ExampleApp.Views.CurrencyAccount"

  alias ExampleApp.Views.Reservation

  defcodec do
    field :account_id, :u64

    group :reservations, of: Reservation

    lookups do
      lookup :reservations_by_id do
        from(:reservations)
        into(:map)
        key(:reservation_id)
      end

      lookup :active_reservations do
        from(:reservations)
        into(:list)
        where(active: true)
      end
    end
  end
end
