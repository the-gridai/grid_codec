defmodule GridCodec.LookupsDslTest do
  use ExUnit.Case, async: true

  defmodule Reservation do
    use GridCodec.Struct, template_id: 900, schema_id: 61, version: 1

    defcodec do
      field :reservation_id, :u64
      field :amount, :u64
      field :active, :bool
    end
  end

  defmodule AccountSnapshot do
    use GridCodec.Struct, template_id: 901, schema_id: 61, version: 1

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

  defmodule PlaceOrder do
    use GridCodec.Struct, template_id: 902, schema_id: 61, version: 1

    defcodec do
      field :order_id, :u64
      field :price, :u64
    end
  end

  defmodule CancelOrder do
    use GridCodec.Struct, template_id: 903, schema_id: 61, version: 1

    defcodec do
      field :cancel_id, :u64
      field :order_id, :u64
    end
  end

  defmodule CommandEnvelope do
    use GridCodec.Struct, template_id: 904, schema_id: 61, version: 1

    defcodec do
      field :account_id, :u64

      batch(:commands, any_of: [PlaceOrder, CancelOrder])

      lookups do
        lookup :commands_by_order_id do
          from(:commands)
          into(:map)
          key(PlaceOrder, :order_id)
          key(CancelOrder, :order_id)
        end
      end
    end
  end

  describe "typed groups" do
    test "new/1 coerces typed group entries into structs" do
      assert {:ok, snapshot} =
               AccountSnapshot.new(%{
                 "account_id" => "7",
                 "reservations" => [
                   %{"reservation_id" => "10", "amount" => "500", "active" => "true"}
                 ]
               })

      assert [%Reservation{} = reservation] = snapshot.reservations
      assert reservation.reservation_id == 10
      assert reservation.amount == 500
      assert reservation.active == true
    end

    test "decode returns a group of typed structs" do
      {:ok, snapshot} =
        AccountSnapshot.new(%{
          account_id: 7,
          reservations: [
            %{reservation_id: 10, amount: 500, active: true},
            %{reservation_id: 11, amount: 250, active: false}
          ]
        })

      {:ok, binary} = AccountSnapshot.encode(snapshot)
      assert {:ok, decoded} = AccountSnapshot.decode(binary)

      reservations = GridCodec.Group.to_list(decoded.reservations)
      assert Enum.map(reservations, & &1.__struct__) == [Reservation, Reservation]
      assert Enum.map(reservations, & &1.reservation_id) == [10, 11]
    end

    test "rejects typed groups with variable-length entry modules" do
      assert_raise CompileError, ~r/variable-length fields/, fn ->
        defmodule VariableReservation do
          use GridCodec.Struct, template_id: 905, schema_id: 61, version: 1

          defcodec do
            field :reservation_id, :u64
            field :note, :string
          end
        end

        defmodule InvalidTypedGroupCodec do
          use GridCodec.Struct, template_id: 906, schema_id: 61, version: 1

          defcodec do
            group :reservations, of: VariableReservation
          end
        end
      end
    end
  end

  describe "group lookups" do
    setup do
      {:ok, snapshot} =
        AccountSnapshot.new(%{
          account_id: 7,
          reservations: [
            %{reservation_id: 10, amount: 500, active: true},
            %{reservation_id: 11, amount: 250, active: false}
          ]
        })

      {:ok, binary} = AccountSnapshot.encode(snapshot)
      {:ok, decoded} = AccountSnapshot.decode(binary)
      %{decoded: decoded}
    end

    test "named and generic helpers project group lookups", %{decoded: decoded} do
      assert {:ok, reservations_by_id} = AccountSnapshot.reservations_by_id(decoded)
      assert %{10 => %Reservation{}, 11 => %Reservation{}} = reservations_by_id

      assert {:ok, same_lookup} = AccountSnapshot.lookup(decoded, :reservations_by_id)
      assert same_lookup == reservations_by_id

      assert {:ok, active_reservations} =
               AccountSnapshot.active_reservations(decoded.reservations)

      assert Enum.map(active_reservations, & &1.reservation_id) == [10]
    end

    test "lookup introspection returns normalized metadata" do
      lookups = AccountSnapshot.__lookups__()
      assert Enum.any?(lookups, &(&1.name == :reservations_by_id))

      assert %{
               source: {:group, :reservations},
               into: :map,
               keys: [{:all, :reservation_id}]
             } = AccountSnapshot.__lookup__(:reservations_by_id)
    end

    test "duplicate map keys are overwritten by the last entry" do
      {:ok, snapshot} =
        AccountSnapshot.new(%{
          account_id: 7,
          reservations: [
            %{reservation_id: 10, amount: 500, active: true},
            %{reservation_id: 10, amount: 700, active: true}
          ]
        })

      assert {:ok, %{10 => reservation}} =
               AccountSnapshot.reservations_by_id(snapshot.reservations)

      assert reservation.amount == 700
    end
  end

  describe "batch lookups" do
    test "lookups support per-type keys across a batch with last write wins" do
      envelope = %CommandEnvelope{
        account_id: 7,
        commands: [
          %PlaceOrder{order_id: 10, price: 100},
          %CancelOrder{cancel_id: 99, order_id: 10}
        ]
      }

      {:ok, binary} = CommandEnvelope.encode(envelope)
      {:ok, decoded} = CommandEnvelope.decode(binary)

      assert {:ok, %{10 => %CancelOrder{cancel_id: 99}}} =
               CommandEnvelope.commands_by_order_id(decoded)
    end

    test "rejects incomplete per-type key coverage" do
      assert_raise CompileError, ~r/missing key declarations/, fn ->
        defmodule InvalidBatchViewCodec do
          use GridCodec.Struct, template_id: 907, schema_id: 61, version: 1

          defcodec do
            batch(:commands, any_of: [PlaceOrder, CancelOrder])

            lookups do
              lookup :commands_by_order_id do
                from(:commands)
                into(:map)
                key(PlaceOrder, :order_id)
              end
            end
          end
        end
      end
    end
  end
end
