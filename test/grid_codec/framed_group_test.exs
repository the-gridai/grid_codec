defmodule GridCodec.FramedGroupTest do
  use ExUnit.Case, async: true

  defmodule Bill do
    use GridCodec.Struct, template_id: 9000, schema_id: 90, version: 1

    defcodec do
      field :bill_id, :string16
      field :amount, :u64
      field :notes, :string16
    end
  end

  defmodule BillDiscount do
    use GridCodec.Struct, template_id: 9001, schema_id: 90, version: 1

    defcodec do
      field :bill_id, :string16
      field :discount_pct, :u32
    end
  end

  defmodule FixedEntry do
    use GridCodec.Struct, template_id: 9002, schema_id: 90, version: 1

    defcodec do
      field :id, :u64
      field :value, :u32
    end
  end

  defmodule BillingSnapshot do
    use GridCodec.Struct, template_id: 9010, schema_id: 90, version: 1

    defcodec do
      field :account_id, :u64
      field :initialized, :bool

      group :bills, of: Bill, framing: :length_prefixed
      group :discounts, of: BillDiscount, framing: :length_prefixed

      lookups do
        lookup :bills_by_id do
          from(:bills)
          into(:map)
          key(:bill_id)
        end
      end
    end
  end

  defmodule FramedFixedEntry do
    use GridCodec.Struct, template_id: 9011, schema_id: 90, version: 1

    defcodec do
      field :label, :string16

      group :entries, of: FixedEntry, framing: :length_prefixed
    end
  end

  describe "basic roundtrip" do
    test "encode/decode with variable-length entries" do
      snapshot = %BillingSnapshot{
        account_id: 42,
        initialized: true,
        bills: [
          %Bill{bill_id: "bill-001", amount: 1000, notes: "First bill"},
          %Bill{bill_id: "bill-002", amount: 2500, notes: "Second bill with longer notes"}
        ],
        discounts: [
          %BillDiscount{bill_id: "bill-001", discount_pct: 10}
        ]
      }

      {:ok, binary} = BillingSnapshot.encode(snapshot)
      {:ok, decoded} = BillingSnapshot.decode(binary)

      assert decoded.account_id == 42
      assert decoded.initialized == true

      assert is_list(decoded.bills)
      assert length(decoded.bills) == 2

      [bill1, bill2] = decoded.bills
      assert bill1.bill_id == "bill-001"
      assert bill1.amount == 1000
      assert bill1.notes == "First bill"
      assert bill2.bill_id == "bill-002"
      assert bill2.amount == 2500
      assert bill2.notes == "Second bill with longer notes"

      assert is_list(decoded.discounts)
      assert [disc] = decoded.discounts
      assert disc.bill_id == "bill-001"
      assert disc.discount_pct == 10
    end

    test "empty framed groups roundtrip" do
      snapshot = %BillingSnapshot{
        account_id: 1,
        initialized: false,
        bills: [],
        discounts: []
      }

      {:ok, binary} = BillingSnapshot.encode(snapshot)
      {:ok, decoded} = BillingSnapshot.decode(binary)

      assert decoded.account_id == 1
      assert decoded.bills == []
      assert decoded.discounts == []
    end

    test "framed groups with fixed-size entries also work" do
      framed = %FramedFixedEntry{
        label: "test",
        entries: [
          %FixedEntry{id: 1, value: 100},
          %FixedEntry{id: 2, value: 200}
        ]
      }

      {:ok, binary} = FramedFixedEntry.encode(framed)
      {:ok, decoded} = FramedFixedEntry.decode(binary)

      assert decoded.label == "test"
      assert length(decoded.entries) == 2
      assert Enum.map(decoded.entries, & &1.id) == [1, 2]
    end
  end

  describe "variable-length entry sizes" do
    test "entries with different payload sizes encode correctly" do
      snapshot = %BillingSnapshot{
        account_id: 1,
        initialized: true,
        bills: [
          %Bill{bill_id: "a", amount: 1, notes: ""},
          %Bill{
            bill_id: "a-much-longer-bill-id",
            amount: 999_999,
            notes: String.duplicate("x", 200)
          }
        ],
        discounts: []
      }

      {:ok, binary} = BillingSnapshot.encode(snapshot)
      {:ok, decoded} = BillingSnapshot.decode(binary)

      [small, large] = decoded.bills
      assert small.bill_id == "a"
      assert small.notes == nil
      assert large.bill_id == "a-much-longer-bill-id"
      assert large.notes == String.duplicate("x", 200)
    end
  end

  describe "lookups work with framed groups" do
    test "map lookup over framed group entries" do
      snapshot = %BillingSnapshot{
        account_id: 42,
        initialized: true,
        bills: [
          %Bill{bill_id: "bill-001", amount: 1000, notes: ""},
          %Bill{bill_id: "bill-002", amount: 2500, notes: ""}
        ],
        discounts: []
      }

      {:ok, binary} = BillingSnapshot.encode(snapshot)
      {:ok, decoded} = BillingSnapshot.decode(binary)

      {:ok, bills_map} = BillingSnapshot.bills_by_id(decoded)

      assert map_size(bills_map) == 2
      assert bills_map["bill-001"].amount == 1000
      assert bills_map["bill-002"].amount == 2500
    end
  end

  describe "new/1 coercion" do
    test "new/1 coerces framed group entries" do
      {:ok, snapshot} =
        BillingSnapshot.new(%{
          "account_id" => "42",
          "initialized" => "true",
          "bills" => [
            %{"bill_id" => "bill-001", "amount" => "1000", "notes" => "test"}
          ],
          "discounts" => []
        })

      assert snapshot.account_id == 42
      assert [%Bill{bill_id: "bill-001", amount: 1000}] = snapshot.bills
    end
  end

  describe "schema introspection" do
    test "framed groups appear in __schema__ groups" do
      schema = BillingSnapshot.__schema__()
      group_names = Enum.map(schema.groups, fn {name, _, _} -> name end)

      assert :bills in group_names
      assert :discounts in group_names
    end
  end

  describe ".grid schema parser" do
    test "parses framing: length_prefixed in group block" do
      grid = """
      @syntax 1

      schema Billing {
        id: 90
        version: 1
      }

      struct Snapshot (template_id: 9020, version: 1) {
        account_id: u64

        group bills {
          framing: length_prefixed
          bill_id: string16
          amount: u64
        }
      }
      """

      {:ok, schema} = GridCodec.Schema.Parser.parse(grid)
      snapshot = schema.structs[:Snapshot]
      assert [group] = snapshot.groups
      assert group.name == :bills
      assert group.framing == :length_prefixed
      assert length(group.fields) == 2
    end

    test "parses group without framing (backward compatible)" do
      grid = """
      @syntax 1

      schema Test {
        id: 90
        version: 1
      }

      struct Msg (template_id: 9021, version: 1) {
        group items {
          id: u64
          value: u32
        }
      }
      """

      {:ok, schema} = GridCodec.Schema.Parser.parse(grid)
      msg = schema.structs[:Msg]
      assert [group] = msg.groups
      assert group.framing == nil
    end
  end

  describe "compile-time validation" do
    test "framing: :length_prefixed allows variable-length entry modules" do
      assert {:ok, _} =
               BillingSnapshot.encode(%BillingSnapshot{
                 account_id: 1,
                 initialized: true,
                 bills: [%Bill{bill_id: "x", amount: 0, notes: ""}],
                 discounts: []
               })
    end

    test "without framing, variable-length of: modules still rejected" do
      assert_raise CompileError, ~r/variable-length fields/, fn ->
        defmodule RejectsVarLengthGroup do
          use GridCodec.Struct, template_id: 9099, schema_id: 90, version: 1

          defcodec do
            field :id, :u64
            group :bills, of: GridCodec.FramedGroupTest.Bill
          end
        end
      end
    end
  end
end
