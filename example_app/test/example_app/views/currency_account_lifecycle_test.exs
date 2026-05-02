defmodule ExampleApp.Views.CurrencyAccountLifecycleTest do
  use ExUnit.Case, async: true

  alias ExampleApp.Views.CurrencyAccount
  alias ExampleApp.Views.Fixtures
  alias ExampleApp.Views.Reservation

  describe "before_encode/2 in the example app" do
    test "materializes durable reservations from the runtime index before encoding" do
      account = Fixtures.runtime_account(4)

      assert account.reservations == []
      assert map_size(account.reservation_index) == 4

      assert {:ok, binary} = CurrencyAccount.encode(account)
      assert {:ok, decoded} = CurrencyAccount.decode(binary)

      assert decoded.reservations |> GridCodec.Group.to_list() |> Enum.map(& &1.reservation_id) ==
               [1, 2, 3, 4]

      assert decoded.reservation_index |> Map.keys() |> Enum.sort() == [1, 2, 3, 4]
    end

    test "new_binary/1 uses the hook for existing runtime structs" do
      account = Fixtures.runtime_account(2)

      assert {:ok, binary} = CurrencyAccount.new_binary(account)
      assert {:ok, decoded} = CurrencyAccount.decode(binary)

      assert decoded.reservation_index |> Map.keys() |> Enum.sort() == [1, 2]
      assert decoded.active_reservation_ids == [1, 2]
    end
  end

  describe "after_decode/2 in the example app" do
    test "rebuilds runtime indexes after direct module decode" do
      assert {:ok, binary} = CurrencyAccount.encode(Fixtures.account(5))
      assert {:ok, decoded} = CurrencyAccount.decode(binary)

      assert decoded.decoded_schema_version == CurrencyAccount.__version__()
      assert decoded.reservation_index |> Map.keys() |> Enum.sort() == [1, 2, 3, 4, 5]
      assert decoded.active_reservation_ids == [1, 2, 4, 5]

      assert %Reservation{reservation_id: 3, active: false} = decoded.reservation_index[3]
    end

    test "rebuilds runtime indexes after GridCodec dispatch decode" do
      GridCodec.Registry.clear_cache()

      assert {:ok, binary} = CurrencyAccount.encode(Fixtures.account(3))
      assert {:ok, %CurrencyAccount{} = decoded} = GridCodec.decode(binary)

      assert decoded.decoded_schema_version == CurrencyAccount.__version__()
      assert decoded.reservation_index |> Map.keys() |> Enum.sort() == [1, 2, 3]
      assert decoded.active_reservation_ids == [1, 2]
    end

    test "uses nil metadata for payload-only decode" do
      assert {:ok, payload} = CurrencyAccount.encode(Fixtures.account(2), header: false)
      assert {:ok, decoded} = CurrencyAccount.decode(payload, header: false)

      assert decoded.decoded_schema_version == nil
      assert decoded.reservation_index |> Map.keys() |> Enum.sort() == [1, 2]
    end
  end

  describe "generated lookups still operate on the persisted group" do
    test "lifecycle indexes agree with generated lookup helpers" do
      assert {:ok, binary} = CurrencyAccount.encode(Fixtures.runtime_account(6))
      assert {:ok, decoded} = CurrencyAccount.decode(binary)

      assert {:ok, reservations_by_id} = CurrencyAccount.reservations_by_id(decoded)
      assert {:ok, active_reservations} = CurrencyAccount.active_reservations(decoded)

      assert Enum.sort(Map.keys(reservations_by_id)) ==
               Enum.sort(Map.keys(decoded.reservation_index))

      assert Enum.map(active_reservations, & &1.reservation_id) ==
               decoded.active_reservation_ids
    end
  end
end
