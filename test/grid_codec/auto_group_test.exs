defmodule GridCodec.AutoGroupTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

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

      {:ok, binary} = OrderBook.encode(struct)
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

      {:ok, binary} = BalanceSnapshot.encode(struct)
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

      {:ok, binary} = WithMixedTypes.encode(struct)
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

      {:ok, binary} = OrderBook.encode(struct)
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

      {:ok, binary} = MultiGroupWithString.encode(struct)
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

      {:ok, binary} = OrderBook.encode(struct)
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

      {:ok, binary} = OrderBook.encode(struct)
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

      {:ok, binary} = OrderBook.encode(struct)
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

      {:ok, binary} = OrdersWithEnum.encode(struct)
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

      {:ok, binary} = OrdersWithEnum.encode(struct)
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

      {:ok, binary} = OrdersWithMultipleEnums.encode(struct)
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

      {:ok, binary} = OrdersWithEnum.encode(struct)
      assert {:ok, decoded} = OrdersWithEnum.decode(binary)

      assert GridCodec.Group.count(decoded.orders) == 0
      assert GridCodec.Group.to_list(decoded.orders) == []
    end
  end

  # ============================================================================
  # Tests: Compile-Time Validation
  # ============================================================================

  # ============================================================================
  # Tests: Parallel to_lists
  # ============================================================================

  describe "to_lists_parallel" do
    test "decodes multiple groups in parallel" do
      struct = %OrderBook{
        symbol: <<1::128>>,
        timestamp: 100,
        bids: for(i <- 1..50, do: %{price: i * 100, quantity: i}),
        asks: for(i <- 1..30, do: %{price: (i + 50) * 100, quantity: i})
      }

      {:ok, binary} = OrderBook.encode(struct)
      {:ok, decoded} = OrderBook.decode(binary)

      [bids, asks] =
        GridCodec.Group.to_lists_parallel(
          [decoded.bids, decoded.asks],
          threshold: 0
        )

      assert length(bids) == 50
      assert length(asks) == 30
      assert Enum.at(bids, 0) == %{price: 100, quantity: 1}
      assert Enum.at(asks, 0) == %{price: 5100, quantity: 1}
    end

    test "falls back to sequential for small groups" do
      struct = %OrderBook{
        symbol: <<1::128>>,
        timestamp: 100,
        bids: [%{price: 100, quantity: 1}],
        asks: [%{price: 200, quantity: 2}]
      }

      {:ok, binary} = OrderBook.encode(struct)
      {:ok, decoded} = OrderBook.decode(binary)

      [bids, asks] = GridCodec.Group.to_lists_parallel([decoded.bids, decoded.asks])
      assert bids == [%{price: 100, quantity: 1}]
      assert asks == [%{price: 200, quantity: 2}]
    end

    test "handles empty list" do
      assert GridCodec.Group.to_lists_parallel([]) == []
    end
  end

  # ============================================================================
  # Property Tests: Groups with Custom Types
  # ============================================================================

  describe "property: groups with custom types roundtrip" do
    property "enum values in groups survive roundtrip" do
      check all(
              n <- StreamData.integer(0..100),
              entries <-
                StreamData.list_of(
                  StreamData.fixed_map(%{
                    order_id: StreamData.map(StreamData.binary(length: 16), & &1),
                    side:
                      StreamData.one_of([
                        StreamData.constant(:buy),
                        StreamData.constant(:sell),
                        StreamData.constant(nil)
                      ]),
                    price: StreamData.integer(0..1_000_000),
                    quantity: StreamData.integer(0..100_000)
                  }),
                  length: n
                )
            ) do
        struct = %OrdersWithEnum{account_id: <<1::128>>, orders: entries}
        {:ok, binary} = OrdersWithEnum.encode(struct)
        {:ok, decoded} = OrdersWithEnum.decode(binary)

        decoded_orders = GridCodec.Group.to_list(decoded.orders)
        assert length(decoded_orders) == n

        Enum.zip(entries, decoded_orders)
        |> Enum.each(fn {input, output} ->
          assert output.order_id == input.order_id
          assert output.side == input.side
          assert output.price == input.price
          assert output.quantity == input.quantity
        end)
      end
    end

    property "multiple enum fields in groups survive roundtrip" do
      sides = StreamData.member_of([:buy, :sell, nil])
      statuses = StreamData.member_of([:open, :filled, :cancelled, nil])

      check all(
              n <- StreamData.integer(0..50),
              entries <-
                StreamData.list_of(
                  StreamData.fixed_map(%{
                    side: sides,
                    status: statuses,
                    price: StreamData.constant(42)
                  }),
                  length: n
                )
            ) do
        struct = %OrdersWithMultipleEnums{id: 1, orders: entries}
        {:ok, binary} = OrdersWithMultipleEnums.encode(struct)
        {:ok, decoded} = OrdersWithMultipleEnums.decode(binary)

        decoded_orders = GridCodec.Group.to_list(decoded.orders)
        assert length(decoded_orders) == n

        Enum.zip(entries, decoded_orders)
        |> Enum.each(fn {input, output} ->
          assert output.side == input.side
          assert output.status == input.status
          assert output.price == input.price
        end)
      end
    end

    property "decimal and positive_decimal fields in groups survive roundtrip" do
      check all(
              n <- StreamData.integer(0..50),
              entries <-
                StreamData.list_of(
                  StreamData.fixed_map(%{
                    instrument_id: StreamData.map(StreamData.binary(length: 16), & &1),
                    available: StreamData.constant(Decimal.new("1000.50")),
                    locked:
                      StreamData.one_of([
                        StreamData.constant(Decimal.new("50.25")),
                        StreamData.constant(nil)
                      ])
                  }),
                  length: n
                )
            ) do
        struct = %BalanceSnapshot{
          account_id: <<1::128>>,
          snapshot_at: 1_700_000_000_000_000,
          balances: entries
        }

        {:ok, binary} = BalanceSnapshot.encode(struct)
        {:ok, decoded} = BalanceSnapshot.decode(binary)

        decoded_balances = GridCodec.Group.to_list(decoded.balances)
        assert length(decoded_balances) == n

        Enum.zip(entries, decoded_balances)
        |> Enum.each(fn {input, output} ->
          assert output.instrument_id == input.instrument_id

          if input.available do
            assert Decimal.equal?(output.available, input.available)
          else
            assert output.available == nil
          end
        end)
      end
    end
  end

  # ============================================================================
  # ============================================================================
  # Tests: Custom type coercion in new/1
  # ============================================================================

  defmodule TopLevelEnumCodec do
    use GridCodec.Struct, template_id: 816, schema_id: 60, version: 1

    alias GridCodec.AutoGroupTest.TestOrderSide
    alias GridCodec.AutoGroupTest.TestOrderStatus

    defcodec do
      field :id, :u64
      field :side, TestOrderSide
      field :status, TestOrderStatus
    end
  end

  describe "custom type coercion" do
    test "enum coerces string to atom in new/1" do
      {:ok, struct} =
        TopLevelEnumCodec.new(%{"id" => "42", "side" => "buy", "status" => "open"})

      assert struct.id == 42
      assert struct.side == :buy
      assert struct.status == :open
    end

    test "enum coerces atom passthrough" do
      {:ok, struct} = TopLevelEnumCodec.new(id: 1, side: :sell, status: :filled)
      assert struct.side == :sell
      assert struct.status == :filled
    end

    test "enum coercion error for invalid string" do
      {:error, %GridCodec.ValidationError{code: :cast_error}} =
        TopLevelEnumCodec.new(id: 1, side: "invalid_value")
    end

    test "enum coercion with nil" do
      {:ok, struct} = TopLevelEnumCodec.new(id: 1, side: nil, status: nil)
      assert struct.side == nil
      assert struct.status == nil
    end

    test "enum coerces in new_binary/1" do
      {:ok, binary} = TopLevelEnumCodec.new_binary(%{"id" => "42", "side" => "sell"})
      assert is_binary(binary)
      {:ok, decoded} = TopLevelEnumCodec.decode(binary)
      assert decoded.side == :sell
    end

    test "group entries coerce from string keys and values" do
      {:ok, struct} =
        OrdersWithEnum.new(%{
          "account_id" => <<1::128>>,
          "orders" => [
            %{"order_id" => <<2::128>>, "side" => "buy", "price" => "100", "quantity" => "10"}
          ]
        })

      [order] = struct.orders
      assert order.side == :buy
      assert order.price == 100
      assert order.quantity == 10
    end

    test "group entry coercion error gives field and group context" do
      {:error, %GridCodec.ValidationError{code: :cast_error} = e} =
        OrdersWithEnum.new(%{
          "account_id" => <<1::128>>,
          "orders" => [
            %{"order_id" => <<2::128>>, "side" => "invalid", "price" => "100", "quantity" => "10"}
          ]
        })

      assert e.details.field == :side
      assert Exception.message(e) =~ "group"
    end

    test "enum roundtrips through string coercion" do
      {:ok, struct} =
        TopLevelEnumCodec.new(%{"id" => "99", "side" => "buy", "status" => "cancelled"})

      {:ok, binary} = TopLevelEnumCodec.encode(struct)
      {:ok, decoded} = TopLevelEnumCodec.decode(binary)
      assert decoded.side == :buy
      assert decoded.status == :cancelled
    end
  end

  # ============================================================================
  # wire_format: option (parameterized types)
  # ============================================================================

  defmodule BalanceWithWireFormat do
    use GridCodec.Struct, template_id: 820, schema_id: 60, version: 1

    defcodec do
      field :id, :u64

      group :balances do
        field :user_id, :u64
        field :amount, {:decimal, scale: 8}, wire_format: :i64
      end
    end
  end

  defmodule TopLevelWireFormat do
    use GridCodec.Struct, template_id: 821, schema_id: 60, version: 1

    defcodec do
      field :id, :u64
      field :price, {:decimal, scale: 8}, wire_format: :i64
      field :quantity, :u32
    end
  end

  defmodule PositiveDecWireFormat do
    use GridCodec.Struct, template_id: 822, schema_id: 60, version: 1

    defcodec do
      field :id, :u64

      group :items do
        field :amount, {:positive_decimal, scale: 4}, wire_format: :u64
      end
    end
  end

  defmodule ParamDecimalNoWire do
    use GridCodec.Struct, template_id: 823, schema_id: 60, version: 1

    defcodec do
      field :id, :u64
      field :price, {:decimal, scale: 8}
      field :quantity, :u32
    end
  end

  describe "wire_format: option" do
    test "group field: encodes Decimal as i64, decodes i64 as Decimal" do
      entries = [
        %{user_id: 1, amount: Decimal.new("123.45000000")},
        %{user_id: 2, amount: Decimal.new("0.00000001")}
      ]

      struct = %BalanceWithWireFormat{id: 42, balances: entries}
      {:ok, binary} = BalanceWithWireFormat.encode(struct)
      {:ok, decoded} = BalanceWithWireFormat.decode(binary)

      balances = GridCodec.Group.to_list(decoded.balances)
      assert length(balances) == 2

      [b1, b2] = balances
      assert %Decimal{} = b1.amount
      assert Decimal.equal?(b1.amount, Decimal.new("123.45000000"))
      assert Decimal.equal?(b2.amount, Decimal.new("0.00000001"))
    end

    test "group field: accepts raw integer (pre-scaled)" do
      struct = %BalanceWithWireFormat{
        id: 1,
        balances: [%{user_id: 1, amount: 12_345_000_000}]
      }

      {:ok, binary} = BalanceWithWireFormat.encode(struct)
      {:ok, decoded} = BalanceWithWireFormat.decode(binary)

      [b] = GridCodec.Group.to_list(decoded.balances)
      assert %Decimal{} = b.amount
      assert Decimal.equal?(b.amount, Decimal.new("123.45000000"))
    end

    test "group field: handles nil as null sentinel" do
      struct = %BalanceWithWireFormat{
        id: 1,
        balances: [%{user_id: 1, amount: nil}]
      }

      {:ok, binary} = BalanceWithWireFormat.encode(struct)
      {:ok, decoded} = BalanceWithWireFormat.decode(binary)

      [b] = GridCodec.Group.to_list(decoded.balances)
      assert b.amount == nil
    end

    test "top-level field: encodes Decimal as i64, decodes as Decimal" do
      struct = %TopLevelWireFormat{
        id: 1,
        price: Decimal.new("99.99000000"),
        quantity: 100
      }

      {:ok, binary} = TopLevelWireFormat.encode(struct)
      {:ok, decoded} = TopLevelWireFormat.decode(binary)

      assert %Decimal{} = decoded.price
      assert Decimal.equal?(decoded.price, Decimal.new("99.99000000"))
      assert decoded.quantity == 100
      assert decoded.id == 1
    end

    test "top-level field: roundtrip with various Decimal values" do
      values = [
        Decimal.new("0"),
        Decimal.new("1.00000000"),
        Decimal.new("-1.00000000"),
        Decimal.new("999999999.99999999")
      ]

      for val <- values do
        struct = %TopLevelWireFormat{id: 1, price: val, quantity: 1}
        {:ok, binary} = TopLevelWireFormat.encode(struct)
        {:ok, decoded} = TopLevelWireFormat.decode(binary)
        assert Decimal.equal?(decoded.price, val), "Failed for #{inspect(val)}"
      end
    end

    test "top-level field: wire format uses i64 size (8 bytes)" do
      assert TopLevelWireFormat.block_length() == 8 + 8 + 4
    end

    test "group field: empty group with wire_format fields" do
      struct = %BalanceWithWireFormat{id: 99, balances: []}
      {:ok, binary} = BalanceWithWireFormat.encode(struct)
      {:ok, decoded} = BalanceWithWireFormat.decode(binary)
      assert decoded.id == 99
      assert GridCodec.Group.to_list(decoded.balances) == []
    end

    test "group field: tuple {mantissa, exponent} input" do
      struct = %BalanceWithWireFormat{
        id: 1,
        balances: [%{user_id: 1, amount: {12345, -2}}]
      }

      {:ok, binary} = BalanceWithWireFormat.encode(struct)
      {:ok, decoded} = BalanceWithWireFormat.decode(binary)
      [b] = GridCodec.Group.to_list(decoded.balances)
      assert %Decimal{} = b.amount
      assert Decimal.equal?(b.amount, Decimal.new("123.45000000"))
    end

    test "compile error: invalid wire_format type" do
      assert_raise CompileError, ~r/Unknown wire_format/, fn ->
        defmodule BadWireFormat do
          use GridCodec.Struct, template_id: 850, schema_id: 60

          defcodec do
            field :x, {:decimal, scale: 2}, wire_format: :nonexistent
          end
        end
      end
    end

    test "compile error: type missing encode_to_wire_ast" do
      assert_raise CompileError, ~r/encode_to_wire_ast/, fn ->
        defmodule BadWireFormatType do
          use GridCodec.Struct, template_id: 851, schema_id: 60

          defcodec do
            field :x, :u64, wire_format: :i32
          end
        end
      end
    end
  end

  # ============================================================================
  # PositiveDecimal with wire_format
  # ============================================================================

  describe "PositiveDecimal with wire_format" do
    test "roundtrip: encodes as u64, decodes as Decimal" do
      struct = %PositiveDecWireFormat{
        id: 1,
        items: [
          %{amount: Decimal.new("99.9999")},
          %{amount: Decimal.new("0.0001")}
        ]
      }

      {:ok, binary} = PositiveDecWireFormat.encode(struct)
      {:ok, decoded} = PositiveDecWireFormat.decode(binary)

      items = GridCodec.Group.to_list(decoded.items)
      assert length(items) == 2
      [i1, i2] = items
      assert %Decimal{} = i1.amount
      assert Decimal.equal?(i1.amount, Decimal.new("99.9999"))
      assert Decimal.equal?(i2.amount, Decimal.new("0.0001"))
    end

    test "nil handled as null sentinel" do
      struct = %PositiveDecWireFormat{id: 1, items: [%{amount: nil}]}
      {:ok, binary} = PositiveDecWireFormat.encode(struct)
      {:ok, decoded} = PositiveDecWireFormat.decode(binary)
      [item] = GridCodec.Group.to_list(decoded.items)
      assert item.amount == nil
    end

    test "raw integer passthrough" do
      struct = %PositiveDecWireFormat{id: 1, items: [%{amount: 999_999}]}
      {:ok, binary} = PositiveDecWireFormat.encode(struct)
      {:ok, decoded} = PositiveDecWireFormat.decode(binary)
      [item] = GridCodec.Group.to_list(decoded.items)
      assert %Decimal{} = item.amount
      assert Decimal.equal?(item.amount, Decimal.new("99.9999"))
    end
  end

  # ============================================================================
  # Parameterized type WITHOUT wire_format (uses default encoding)
  # ============================================================================

  describe "parameterized type auto-infers wire_format" do
    test "{:decimal, scale: N} auto-selects wire_format: :i64" do
      assert ParamDecimalNoWire.block_length() == 8 + 8 + 4
    end

    test "roundtrip: Decimal survives auto-inferred i64 wire format" do
      struct = %ParamDecimalNoWire{
        id: 1,
        price: Decimal.new("123.45600000"),
        quantity: 50
      }

      {:ok, binary} = ParamDecimalNoWire.encode(struct)
      {:ok, decoded} = ParamDecimalNoWire.decode(binary)

      assert decoded.id == 1
      assert %Decimal{} = decoded.price
      assert Decimal.equal?(decoded.price, Decimal.new("123.45600000"))
      assert decoded.quantity == 50
    end

    test "nil price roundtrip with auto-inferred wire format" do
      struct = %ParamDecimalNoWire{id: 1, price: nil, quantity: 10}
      {:ok, binary} = ParamDecimalNoWire.encode(struct)
      {:ok, decoded} = ParamDecimalNoWire.decode(binary)
      assert decoded.price == nil
    end
  end

  # ============================================================================
  # Property tests for wire_format roundtrips
  # ============================================================================

  describe "property: wire_format roundtrips" do
    property "Decimal values survive wire_format: :i64 roundtrip" do
      check all(
              coef <- StreamData.integer(0..999_999_999_999),
              sign <- StreamData.member_of([1, -1])
            ) do
        dec = %Decimal{sign: sign, coef: coef, exp: -8}
        struct = %TopLevelWireFormat{id: 1, price: dec, quantity: 1}
        {:ok, binary} = TopLevelWireFormat.encode(struct)
        {:ok, decoded} = TopLevelWireFormat.decode(binary)
        assert Decimal.equal?(decoded.price, dec)
      end
    end

    property "nil and non-nil Decimal values roundtrip in groups" do
      check all(
              n <- StreamData.integer(0..20),
              entries <-
                StreamData.list_of(
                  StreamData.fixed_map(%{
                    user_id: StreamData.integer(1..1_000_000),
                    amount:
                      StreamData.one_of([
                        StreamData.constant(nil),
                        StreamData.map(
                          StreamData.integer(0..99_999_999_999),
                          &Decimal.new(1, &1, -8)
                        )
                      ])
                  }),
                  length: n
                )
            ) do
        struct = %BalanceWithWireFormat{id: 1, balances: entries}
        {:ok, binary} = BalanceWithWireFormat.encode(struct)
        {:ok, decoded} = BalanceWithWireFormat.decode(binary)
        decoded_list = GridCodec.Group.to_list(decoded.balances)
        assert length(decoded_list) == n

        Enum.zip(entries, decoded_list)
        |> Enum.each(fn {input, output} ->
          assert output.user_id == input.user_id

          if input.amount do
            assert Decimal.equal?(output.amount, input.amount)
          else
            assert output.amount == nil
          end
        end)
      end
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
