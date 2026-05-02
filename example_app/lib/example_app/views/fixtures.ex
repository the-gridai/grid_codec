defmodule ExampleApp.Views.Fixtures do
  @moduledoc """
  Shared sample data builders for typed-group and lookup examples.
  """

  alias ExampleApp.Views.CommandEnvelope
  alias ExampleApp.Views.CurrencyAccount
  alias ExampleApp.Views.PlaceReservation
  alias ExampleApp.Views.ReleaseReservation
  alias ExampleApp.Views.Reservation

  @base_us 1_763_000_000_000_000

  @doc """
  Builds a sample currency account with `count` reservations.
  """
  def account(count \\ 10_000) when is_integer(count) and count >= 0 do
    %CurrencyAccount{
      account_id: 42,
      reservations:
        for i <- 1..count do
          %Reservation{
            reservation_id: i,
            order_id: 1_000_000 + i,
            amount: 100_000 + rem(i, 5000),
            active: rem(i, 3) != 0,
            expires_at: DateTime.from_unix!(@base_us + i, :microsecond)
          }
        end
    }
  end

  @doc """
  Builds a sample account in the runtime shape used by aggregate command
  handlers: reservations live in a virtual index and are materialized into the
  durable group by `CurrencyAccount.before_encode/2`.
  """
  def runtime_account(count \\ 10_000) when is_integer(count) and count >= 0 do
    reservations =
      for i <- 1..count do
        %Reservation{
          reservation_id: i,
          order_id: 1_000_000 + i,
          amount: 100_000 + rem(i, 5000),
          active: rem(i, 3) != 0,
          expires_at: DateTime.from_unix!(@base_us + i, :microsecond)
        }
      end

    %CurrencyAccount{
      account_id: 42,
      reservations: [],
      reservation_index: Map.new(reservations, &{&1.reservation_id, &1}),
      active_reservation_ids:
        reservations
        |> Enum.filter(& &1.active)
        |> Enum.map(& &1.reservation_id)
    }
  end

  @doc """
  Builds a sample command envelope with `count` heterogeneous commands.
  """
  def command_envelope(count \\ 10_000) when is_integer(count) and count >= 0 do
    %CommandEnvelope{
      account_id: 42,
      commands:
        for i <- 1..count do
          timestamp = @base_us + i

          if rem(i, 2) == 0 do
            %PlaceReservation{
              reservation_id: i,
              amount: 100_000 + rem(i, 5000),
              requested_at: timestamp
            }
          else
            %ReleaseReservation{
              reservation_id: i,
              reason_code: rem(i, 8),
              released_at: timestamp
            }
          end
        end
    }
  end
end
