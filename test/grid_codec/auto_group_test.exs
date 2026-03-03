defmodule GridCodec.AutoGroupTest do
  use ExUnit.Case, async: true

  # ============================================================================
  # Test Modules: Auto-generated group entry codecs
  # ============================================================================

  defmodule OrderBook do
    use GridCodec.Struct, template_id: 800, schema_id: 60, version: 1

    defcodec do
      field :symbol, :uuid
      field :timestamp, :u64

      group :bids do
        field :price, :u64
        field :quantity, :u32
      end

      group :asks do
        field :price, :u64
        field :quantity, :u32
      end
    end
  end

  defmodule BalanceSnapshot do
    use GridCodec.Struct, template_id: 801, schema_id: 60, version: 1

    defcodec do
      field :account_id, :uuid
      field :snapshot_at, :timestamp_us

      group :balances do
        field :instrument_id, :uuid
        field :available, :decimal
        field :locked, :decimal
      end
    end
  end

  defmodule WithMixedTypes do
    use GridCodec.Struct, template_id: 802, schema_id: 60, version: 1

    defcodec do
      field :id, :u64

      group :entries do
        field :active, :bool
        field :count, :u32
        field :score, :i64
        field :tag, :u8
      end
    end
  end

  defmodule FixedOnlyWithGroup do
    use GridCodec.Struct, template_id: 803, schema_id: 60, version: 1

    defcodec do
      field :id, :u64

      group :items do
        field :value, :u32
      end
    end
  end

  defmodule MultiGroupWithString do
    use GridCodec.Struct, template_id: 804, schema_id: 60, version: 1

    defcodec do
      field :id, :u64

      group :levels do
        field :price, :u64
        field :qty, :u32
      end

      field :name, :string
    end
  end

  # ============================================================================
  # Tests: Basic Roundtrip
  # ============================================================================

  describe "basic roundtrip with auto-generated groups" do
    test "encode and decode OrderBook with bids and asks" do
      uuid = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>
      ts = 1_700_000_000_000_000

      struct = %OrderBook{
        symbol: uuid,
        timestamp: ts,
        bids: [%{price: 100, quantity: 10}, %{price: 99, quantity: 20}],
        asks: [%{price: 101, quantity: 15}]
      }

      binary = OrderBook.encode(struct)
      assert {:ok, decoded} = OrderBook.decode(binary)

      assert decoded.symbol == uuid
      assert decoded.timestamp == ts

      bids = GridCodec.Group.to_list(decoded.bids)
      assert length(bids) == 2
      assert Enum.at(bids, 0) == %{price: 100, quantity: 10}
      assert Enum.at(bids, 1) == %{price: 99, quantity: 20}

      asks = GridCodec.Group.to_list(decoded.asks)
      assert length(asks) == 1
      assert Enum.at(asks, 0) == %{price: 101, quantity: 15}
    end

    test "encode and decode with decimal fields in group" do
      uuid = <<1::128>>
      ts = System.system_time(:microsecond)

      struct = %BalanceSnapshot{
        account_id: uuid,
        snapshot_at: ts,
        balances: [
          %{
            instrument_id: <<2::128>>,
            available: Decimal.new("1000.50"),
            locked: Decimal.new("50.25")
          },
          %{instrument_id: <<3::128>>, available: Decimal.new("500"), locked: nil}
        ]
      }

      binary = BalanceSnapshot.encode(struct)
      assert {:ok, decoded} = BalanceSnapshot.decode(binary)

      assert decoded.account_id == uuid

      balances = GridCodec.Group.to_list(decoded.balances)
      assert length(balances) == 2

      b1 = Enum.at(balances, 0)
      assert b1.instrument_id == <<2::128>>
      assert Decimal.equal?(b1.available, Decimal.new("1000.50"))
      assert Decimal.equal?(b1.locked, Decimal.new("50.25"))

      b2 = Enum.at(balances, 1)
      assert b2.instrument_id == <<3::128>>
      assert Decimal.equal?(b2.available, Decimal.new("500"))
      assert b2.locked == nil
    end

    test "mixed types in group entries" do
      struct = %WithMixedTypes{
        id: 42,
        entries: [
          %{active: true, count: 100, score: -500, tag: 7},
          %{active: false, count: 0, score: 9_999_999, tag: 42}
        ]
      }

      binary = WithMixedTypes.encode(struct)
      assert {:ok, decoded} = WithMixedTypes.decode(binary)

      entries = GridCodec.Group.to_list(decoded.entries)
      assert length(entries) == 2

      e1 = Enum.at(entries, 0)
      assert e1.active == true
      assert e1.count == 100
      assert e1.score == -500
      assert e1.tag == 7

      e2 = Enum.at(entries, 1)
      assert e2.active == false
      assert e2.count == 0
      assert e2.score == 9_999_999
      assert e2.tag == 42
    end
  end

  # ============================================================================
  # Tests: Empty Groups
  # ============================================================================

  describe "empty groups" do
    test "encode and decode with empty group list" do
      struct = %OrderBook{
        symbol: <<1::128>>,
        timestamp: 100,
        bids: [],
        asks: []
      }

      binary = OrderBook.encode(struct)
      assert {:ok, decoded} = OrderBook.decode(binary)

      assert GridCodec.Group.count(decoded.bids) == 0
      assert GridCodec.Group.count(decoded.asks) == 0
      assert GridCodec.Group.to_list(decoded.bids) == []
      assert GridCodec.Group.to_list(decoded.asks) == []
    end

    test "default struct has empty groups" do
      struct = %FixedOnlyWithGroup{id: 1}
      assert struct.items == []
    end
  end

  # ============================================================================
  # Tests: Group with Variable-Length Sibling Fields
  # ============================================================================

  describe "groups alongside variable-length fields" do
    test "group + string field roundtrip" do
      struct = %MultiGroupWithString{
        id: 99,
        levels: [%{price: 200, qty: 5}, %{price: 300, qty: 10}],
        name: "test market"
      }

      binary = MultiGroupWithString.encode(struct)
      assert {:ok, decoded} = MultiGroupWithString.decode(binary)

      assert decoded.id == 99
      assert decoded.name == "test market"

      levels = GridCodec.Group.to_list(decoded.levels)
      assert length(levels) == 2
      assert Enum.at(levels, 0) == %{price: 200, qty: 5}
    end
  end

  # ============================================================================
  # Tests: Nullable Fields in Group Entries
  # ============================================================================

  describe "nullable fields in group entries" do
    test "nil values in group entry fields encode as null sentinels" do
      struct = %OrderBook{
        symbol: <<1::128>>,
        timestamp: 100,
        bids: [%{price: nil, quantity: nil}],
        asks: []
      }

      binary = OrderBook.encode(struct)
      assert {:ok, decoded} = OrderBook.decode(binary)

      bids = GridCodec.Group.to_list(decoded.bids)
      assert length(bids) == 1

      bid = Enum.at(bids, 0)
      assert bid.price == nil
      assert bid.quantity == nil
    end
  end

  # ============================================================================
  # Tests: Group Random Access
  # ============================================================================

  describe "random access on auto-generated groups" do
    test "get_entry works at arbitrary index" do
      struct = %OrderBook{
        symbol: <<1::128>>,
        timestamp: 100,
        bids:
          for i <- 1..50 do
            %{price: i * 100, quantity: i}
          end,
        asks: []
      }

      binary = OrderBook.encode(struct)
      {:ok, decoded} = OrderBook.decode(binary)

      assert {:ok, %{price: 2500, quantity: 25}} = GridCodec.Group.get_entry(decoded.bids, 24)
      assert {:ok, %{price: 100, quantity: 1}} = GridCodec.Group.get_entry(decoded.bids, 0)
      assert {:ok, %{price: 5000, quantity: 50}} = GridCodec.Group.get_entry(decoded.bids, 49)
    end

    test "stream and filter on auto-generated group" do
      struct = %OrderBook{
        symbol: <<1::128>>,
        timestamp: 100,
        bids:
          for i <- 1..20 do
            %{price: i * 10, quantity: i}
          end,
        asks: []
      }

      binary = OrderBook.encode(struct)
      {:ok, decoded} = OrderBook.decode(binary)

      big_bids =
        decoded.bids
        |> GridCodec.Group.stream()
        |> Stream.filter(fn e -> e.price > 150 end)
        |> Enum.to_list()

      assert length(big_bids) == 5
      assert Enum.all?(big_bids, fn e -> e.price > 150 end)
    end
  end

  # ============================================================================
  # Tests: Custom Enum Types in Groups
  # ============================================================================

  defmodule TestOrderSide do
    use GridCodec.Types.Enum, encoding: :u8

    defenum do
      value(:buy)
      value(:sell)
    end
  end

  defmodule TestOrderStatus do
    use GridCodec.Types.Enum, encoding: :u8

    defenum do
      value(:open)
      value(:filled)
      value(:cancelled)
    end
  end

  defmodule OrdersWithEnum do
    use GridCodec.Struct, template_id: 810, schema_id: 60, version: 1

    alias GridCodec.AutoGroupTest.TestOrderSide

    defcodec do
      field :account_id, :uuid

      group :orders do
        field :order_id, :uuid
        field :side, TestOrderSide
        field :price, :u64
        field :quantity, :u32
      end
    end
  end

  defmodule OrdersWithMultipleEnums do
    use GridCodec.Struct, template_id: 811, schema_id: 60, version: 1

    alias GridCodec.AutoGroupTest.TestOrderSide
    alias GridCodec.AutoGroupTest.TestOrderStatus

    defcodec do
      field :id, :u64

      group :orders do
        field :side, TestOrderSide
        field :status, TestOrderStatus
        field :price, :u64
      end
    end
  end

  describe "custom enum types in groups" do
    test "enum field in group roundtrips atom values" do
      uuid = <<1::128>>

      struct = %OrdersWithEnum{
        account_id: uuid,
        orders: [
          %{order_id: <<2::128>>, side: :buy, price: 100, quantity: 10},
          %{order_id: <<3::128>>, side: :sell, price: 200, quantity: 5}
        ]
      }

      binary = OrdersWithEnum.encode(struct)
      assert {:ok, decoded} = OrdersWithEnum.decode(binary)

      assert decoded.account_id == uuid

      orders = GridCodec.Group.to_list(decoded.orders)
      assert length(orders) == 2

      o1 = Enum.at(orders, 0)
      assert o1.order_id == <<2::128>>
      assert o1.side == :buy
      assert o1.price == 100
      assert o1.quantity == 10

      o2 = Enum.at(orders, 1)
      assert o2.order_id == <<3::128>>
      assert o2.side == :sell
      assert o2.price == 200
      assert o2.quantity == 5
    end

    test "nil enum value in group entry roundtrips as nil" do
      struct = %OrdersWithEnum{
        account_id: <<1::128>>,
        orders: [
          %{order_id: <<2::128>>, side: nil, price: 100, quantity: 10}
        ]
      }

      binary = OrdersWithEnum.encode(struct)
      assert {:ok, decoded} = OrdersWithEnum.decode(binary)

      [order] = GridCodec.Group.to_list(decoded.orders)
      assert order.side == nil
    end

    test "multiple enum fields in same group" do
      struct = %OrdersWithMultipleEnums{
        id: 42,
        orders: [
          %{side: :buy, status: :open, price: 100},
          %{side: :sell, status: :filled, price: 200},
          %{side: :buy, status: :cancelled, price: 300}
        ]
      }

      binary = OrdersWithMultipleEnums.encode(struct)
      assert {:ok, decoded} = OrdersWithMultipleEnums.decode(binary)

      orders = GridCodec.Group.to_list(decoded.orders)
      assert length(orders) == 3

      assert Enum.at(orders, 0) == %{side: :buy, status: :open, price: 100}
      assert Enum.at(orders, 1) == %{side: :sell, status: :filled, price: 200}
      assert Enum.at(orders, 2) == %{side: :buy, status: :cancelled, price: 300}
    end

    test "empty group with enum fields" do
      struct = %OrdersWithEnum{
        account_id: <<1::128>>,
        orders: []
      }

      binary = OrdersWithEnum.encode(struct)
      assert {:ok, decoded} = OrdersWithEnum.decode(binary)

      assert GridCodec.Group.count(decoded.orders) == 0
      assert GridCodec.Group.to_list(decoded.orders) == []
    end
  end

  # ============================================================================
  # Tests: Compile-Time Validation
  # ============================================================================

  describe "compile-time validation" do
    test "variable-length field in group raises CompileError" do
      assert_raise CompileError, ~r/variable-length fields/, fn ->
        defmodule BadGroup do
          use GridCodec.Struct, template_id: 899, schema_id: 60, version: 1

          defcodec do
            field :id, :u64

            group :items do
              field :name, :string
            end
          end
        end
      end
    end
  end
end
