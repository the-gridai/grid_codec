defmodule ExampleApp.Views.CurrencyAccount do
  @moduledoc """
  Example aggregate-style codec using typed groups, generated lookups, and
  struct lifecycle hooks.

  The persisted `.grid` shape keeps durable reservation entries in the
  `reservations` group. Runtime command handlers can keep derived indexes in
  virtual fields; `before_encode/2` materializes the durable group when needed
  and `after_decode/2` rebuilds the indexes after loading a snapshot.
  """

  use GridCodec.Struct,
    template_id: 302,
    schema_id: 300,
    name: "ExampleApp.Views.CurrencyAccount"

  alias ExampleApp.Views.Reservation

  defcodec do
    field :account_id, :u64, doc: "Identifier of the currency account being materialized."

    group :reservations,
      of: Reservation,
      doc: "Active and historical reservations held against the account."

    virtual :reservation_index, default: %{}, validate: false
    virtual :active_reservation_ids, default: [], validate: false
    virtual :decoded_schema_version, validate: false

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

  @impl GridCodec.Struct
  def before_encode(%__MODULE__{reservations: [], reservation_index: index} = struct, _header)
      when map_size(index) > 0 do
    reservations =
      index
      |> Map.values()
      |> Enum.sort_by(& &1.reservation_id)

    %{struct | reservations: reservations}
  end

  def before_encode(%__MODULE__{} = struct, _header), do: struct

  @impl GridCodec.Struct
  def after_decode(%__MODULE__{} = struct, header) do
    reservations = materialize_reservations(struct.reservations)

    {:ok,
     %{
       struct
       | reservation_index: Map.new(reservations, &{&1.reservation_id, &1}),
         active_reservation_ids: active_reservation_ids(reservations),
         decoded_schema_version: header && header.version
     }}
  end

  defp materialize_reservations(%GridCodec.Group{} = reservations),
    do: GridCodec.Group.to_list(reservations)

  defp materialize_reservations(reservations) when is_list(reservations), do: reservations

  defp active_reservation_ids(reservations) do
    reservations
    |> Enum.filter(& &1.active)
    |> Enum.map(& &1.reservation_id)
  end
end
