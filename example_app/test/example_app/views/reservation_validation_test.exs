defmodule ExampleApp.Views.ReservationValidationTest do
  use ExUnit.Case, async: true

  alias ExampleApp.Views.Reservation

  test "new/1 enforces reservation amount invariant" do
    assert {:error, %GridCodec.ValidationError{code: :invariant_failed} = error} =
             Reservation.new(%{
               reservation_id: 1,
               order_id: 2,
               amount: 0,
               active: true,
               expires_at: DateTime.from_unix!(1_700_000_000, :second)
             })

    assert error.details.name == :positive_amount
  end

  test "validate_struct/1 returns ok for valid reservation" do
    reservation = %Reservation{
      reservation_id: 1,
      order_id: 2,
      amount: 5,
      active: true,
      expires_at: DateTime.from_unix!(1_700_000_000, :second)
    }

    assert {:ok, ^reservation} = Reservation.validate_struct(reservation)
  end
end
