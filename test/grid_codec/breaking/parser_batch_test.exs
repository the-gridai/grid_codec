defmodule GridCodec.Breaking.ParserBatchTest do
  use ExUnit.Case, async: true

  alias GridCodec.Schema.Parser
  alias GridCodec.Schema.Parser.BatchDef
  alias GridCodec.Schema.Parser.StructDef

  describe "batch parsing" do
    test "parses batch block with any_of and strategy" do
      schema = """
      schema Test { id: 1 }

      struct PlaceOrder (template_id: 10) {
        order_id: uuid_string
      }

      struct CancelOrder (template_id: 11) {
        order_id: uuid_string
      }

      struct OrderBook (template_id: 1) {
        id: uuid_string

        batch commands {
          any_of: [PlaceOrder, CancelOrder]
          strategy: padded_union
        }
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      order_book = parsed.structs[:OrderBook]
      assert %StructDef{batches: [batch]} = order_book

      assert %BatchDef{
               name: :commands,
               any_of: [:PlaceOrder, :CancelOrder],
               strategy: :padded_union
             } = batch
    end

    test "parses batch with typed_frames strategy" do
      schema = """
      schema Test { id: 1 }

      struct OrderBook (template_id: 1) {
        id: uuid_string

        batch events {
          any_of: [Alpha, Beta, Gamma]
          strategy: typed_frames
        }
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      batch = hd(parsed.structs[:OrderBook].batches)
      assert batch.strategy == :typed_frames
      assert batch.any_of == [:Alpha, :Beta, :Gamma]
    end

    test "defaults strategy to padded_union" do
      schema = """
      schema Test { id: 1 }

      struct Container (template_id: 1) {
        batch items {
          any_of: [A, B]
        }
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      batch = hd(parsed.structs[:Container].batches)
      assert batch.strategy == :padded_union
    end

    test "struct with fields, groups, and batches together" do
      schema = """
      schema Test { id: 1 }

      struct Full (template_id: 1) {
        id: uuid_string
        price: u64

        group fills {
          price: u64
          qty: u32
        }

        batch commands {
          any_of: [X, Y]
          strategy: typed_frames
        }
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      full = parsed.structs[:Full]
      assert length(full.fields) == 2
      assert length(full.groups) == 1
      assert length(full.batches) == 1
    end

    test "multiple batches in one struct" do
      schema = """
      schema Test { id: 1 }

      struct Multi (template_id: 1) {
        batch first {
          any_of: [A, B]
          strategy: padded_union
        }

        batch second {
          any_of: [C, D, E]
          strategy: typed_frames
        }
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      batches = parsed.structs[:Multi].batches
      assert length(batches) == 2
      assert Enum.map(batches, & &1.name) == [:first, :second]
    end

    test "struct without batches still works" do
      schema = """
      schema Test { id: 1 }

      struct Simple (template_id: 1) {
        id: uuid_string
        price: u64
      }
      """

      assert {:ok, parsed} = Parser.parse(schema)
      assert parsed.structs[:Simple].batches == []
    end
  end
end
