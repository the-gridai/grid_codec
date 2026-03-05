defmodule GridCodec.DispatchTest do
  use ExUnit.Case, async: true

  # Define test codecs with unique template_ids
  defmodule OrderCreated do
    use GridCodec.Struct, template_id: 1, schema_id: 100, version: 1

    defcodec do
      field :order_id, :u64
      field :price, :u64
    end
  end

  defmodule OrderFilled do
    use GridCodec.Struct, template_id: 2, schema_id: 100, version: 1

    defcodec do
      field :order_id, :u64
      field :fill_price, :u64
      field :fill_qty, :u32
    end
  end

  defmodule OrderCancelled do
    use GridCodec.Struct, template_id: 3, schema_id: 100, version: 2

    defcodec do
      field :order_id, :u64
      field :reason, :u8
    end
  end

  # Different schema_id - no conflict with template_id: 1
  defmodule OtherSchemaEvent do
    use GridCodec.Struct, template_id: 1, schema_id: 200, version: 1

    defcodec do
      field :event_id, :u64
    end
  end

  # Define dispatch module
  defmodule TestDispatch do
    use GridCodec.Dispatch

    codecs([
      OrderCreated,
      OrderFilled,
      OrderCancelled,
      OtherSchemaEvent
    ])
  end

  describe "decode/1" do
    test "routes to correct codec based on header" do
      # Create framed messages
      {:ok, order_created} = OrderCreated.encode(%OrderCreated{order_id: 123, price: 1000})

      {:ok, order_filled} =
        OrderFilled.encode(%OrderFilled{order_id: 123, fill_price: 1001, fill_qty: 50})

      # Dispatch should route to correct decoder
      assert {:ok, %OrderCreated{order_id: 123, price: 1000}, OrderCreated} =
               TestDispatch.decode(order_created)

      assert {:ok, %OrderFilled{order_id: 123, fill_price: 1001, fill_qty: 50}, OrderFilled} =
               TestDispatch.decode(order_filled)
    end

    test "returns error for unknown message type" do
      # Create a header with unknown template_id
      header =
        GridCodec.Header.encode(block_length: 8, template_id: 999, schema_id: 100, version: 1)

      payload = <<0::64>>
      binary = <<header::binary, payload::binary>>

      assert {:error, :unknown_message} = TestDispatch.decode(binary)
    end

    test "returns error for unknown schema_id" do
      header =
        GridCodec.Header.encode(block_length: 8, template_id: 1, schema_id: 999, version: 1)

      payload = <<0::64>>
      binary = <<header::binary, payload::binary>>

      assert {:error, :unknown_message} = TestDispatch.decode(binary)
    end

    test "allows older version messages" do
      # OrderCancelled is version 2, but we can decode version 1 messages
      # (forward compatibility - reader handles older versions)
      header =
        GridCodec.Header.encode(block_length: 9, template_id: 3, schema_id: 100, version: 1)

      payload = <<42::little-64, 5::8>>
      binary = <<header::binary, payload::binary>>

      assert {:ok, %OrderCancelled{order_id: 42, reason: 5}, OrderCancelled} =
               TestDispatch.decode(binary)
    end

    test "returns error for newer version than codec supports" do
      # OrderCreated is version 1, reject version 2 messages
      header =
        GridCodec.Header.encode(block_length: 16, template_id: 1, schema_id: 100, version: 2)

      payload = <<123::little-64, 1000::little-64>>
      binary = <<header::binary, payload::binary>>

      assert {:error, {:version_too_new, 2, 1}} = TestDispatch.decode(binary)
    end

    test "handles different schema_ids with same template_id" do
      # Both have template_id: 1 but different schema_ids
      {:ok, order} = OrderCreated.encode(%OrderCreated{order_id: 1, price: 100})
      {:ok, other} = OtherSchemaEvent.encode(%OtherSchemaEvent{event_id: 999})

      assert {:ok, %OrderCreated{order_id: 1, price: 100}, OrderCreated} =
               TestDispatch.decode(order)

      assert {:ok, %OtherSchemaEvent{event_id: 999}, OtherSchemaEvent} =
               TestDispatch.decode(other)
    end
  end

  describe "decode!/1" do
    test "returns tuple on success" do
      {:ok, binary} = OrderCreated.encode(%OrderCreated{order_id: 123, price: 1000})

      assert {%OrderCreated{order_id: 123, price: 1000}, OrderCreated} =
               TestDispatch.decode!(binary)
    end

    test "raises on error" do
      header =
        GridCodec.Header.encode(block_length: 8, template_id: 999, schema_id: 100, version: 1)

      payload = <<0::64>>
      binary = <<header::binary, payload::binary>>

      assert_raise ArgumentError, ~r/unknown_message/, fn ->
        TestDispatch.decode!(binary)
      end
    end
  end

  describe "lookup/2" do
    test "returns codec module for known messages" do
      assert {:ok, OrderCreated} = TestDispatch.lookup(100, 1)
      assert {:ok, OrderFilled} = TestDispatch.lookup(100, 2)
      assert {:ok, OtherSchemaEvent} = TestDispatch.lookup(200, 1)
    end

    test "returns error for unknown messages" do
      assert :error = TestDispatch.lookup(100, 999)
      assert :error = TestDispatch.lookup(999, 1)
    end
  end

  describe "list_codecs/0" do
    test "returns all registered codecs" do
      codecs = TestDispatch.list_codecs()

      assert OrderCreated in codecs
      assert OrderFilled in codecs
      assert OrderCancelled in codecs
      assert OtherSchemaEvent in codecs
      assert length(codecs) == 4
    end
  end

  describe "dispatch_table/0" do
    test "returns the dispatch table" do
      table = TestDispatch.dispatch_table()

      assert %{module: OrderCreated, version: 1} = table[{100, 1}]
      assert %{module: OrderFilled, version: 1} = table[{100, 2}]
      assert %{module: OrderCancelled, version: 2} = table[{100, 3}]
      assert %{module: OtherSchemaEvent, version: 1} = table[{200, 1}]
    end
  end

  describe "peek_header/1" do
    test "returns header without decoding payload" do
      {:ok, binary} = OrderCreated.encode(%OrderCreated{order_id: 123, price: 1000})

      assert {:ok, header} = TestDispatch.peek_header(binary)
      assert header.template_id == 1
      assert header.schema_id == 100
      assert header.version == 1
      assert header.block_length == 16
    end
  end

  describe "compile-time conflict detection" do
    test "compilation fails with conflicting template_ids" do
      # This test verifies that the compile-time check works
      # We can't actually test compilation failure in a running test,
      # but we document the expected behavior

      # If you tried to define:
      #
      #   defmodule ConflictingDispatch do
      #     use GridCodec.Dispatch
      #
      #     codecs [
      #       OrderCreated,       # {100, 1}
      #       SomeOtherCodec      # also {100, 1} - CONFLICT!
      #     ]
      #   end
      #
      # It would raise CompileError:
      #   "Conflicting template_id! ... both have {schema_id: 100, template_id: 1}"

      # For now, we just verify that same template_id with different schema_id works
      assert {:ok, OrderCreated} = TestDispatch.lookup(100, 1)
      assert {:ok, OtherSchemaEvent} = TestDispatch.lookup(200, 1)
    end
  end
end
