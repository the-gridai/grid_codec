defmodule GridCodec.MultiCodecTest do
  use ExUnit.Case, async: false

  alias GridCodec.Envelope

  # Clear the registry cache at the start of each test to ensure
  # our dynamically-defined test codecs are found
  setup do
    GridCodec.Registry.clear_cache()
    :ok
  end

  # Define multiple codecs with different schema/template IDs
  defmodule Events do
    defmodule OrderCreated do
      use GridCodec.Struct, template_id: 1, schema_id: 900

      defcodec do
        field :order_id, :uuid, presence: :required
        field :price, :u64
        field :quantity, :u32
      end
    end

    defmodule OrderFilled do
      use GridCodec.Struct, template_id: 2, schema_id: 900

      defcodec do
        field :order_id, :uuid, presence: :required
        field :fill_price, :u64
        field :fill_quantity, :u32
        field :timestamp, :i64
      end
    end

    defmodule OrderCancelled do
      use GridCodec.Struct, template_id: 3, schema_id: 900

      defcodec do
        field :order_id, :uuid, presence: :required
        field :reason_code, :u8
      end
    end
  end

  # Different schema - same template_id should be fine
  defmodule Trades do
    defmodule TradeExecuted do
      use GridCodec.Struct, template_id: 1, schema_id: 901

      defcodec do
        field :trade_id, :uuid, presence: :required
        field :price, :u64
        field :quantity, :u32
      end
    end
  end

  describe "multi-codec dispatch" do
    test "encodes and decodes OrderCreated" do
      uuid = <<1::128>>
      order = %Events.OrderCreated{order_id: uuid, price: 1000, quantity: 10}

      binary = GridCodec.encode(order)
      {:ok, decoded} = GridCodec.decode(binary)

      assert %Events.OrderCreated{} = decoded
      assert decoded.order_id == uuid
      assert decoded.price == 1000
      assert decoded.quantity == 10
    end

    test "encodes and decodes OrderFilled" do
      uuid = <<2::128>>

      fill = %Events.OrderFilled{
        order_id: uuid,
        fill_price: 1001,
        fill_quantity: 5,
        timestamp: 1_234_567_890
      }

      binary = GridCodec.encode(fill)
      {:ok, decoded} = GridCodec.decode(binary)

      assert %Events.OrderFilled{} = decoded
      assert decoded.order_id == uuid
      assert decoded.fill_price == 1001
      assert decoded.fill_quantity == 5
      assert decoded.timestamp == 1_234_567_890
    end

    test "encodes and decodes OrderCancelled" do
      uuid = <<3::128>>
      cancel = %Events.OrderCancelled{order_id: uuid, reason_code: 42}

      binary = GridCodec.encode(cancel)
      {:ok, decoded} = GridCodec.decode(binary)

      assert %Events.OrderCancelled{} = decoded
      assert decoded.order_id == uuid
      assert decoded.reason_code == 42
    end

    test "same template_id in different schemas is correctly dispatched" do
      # Both have template_id: 1, but different schema_id
      order_uuid = <<10::128>>
      trade_uuid = <<20::128>>

      order = %Events.OrderCreated{order_id: order_uuid, price: 100, quantity: 1}
      trade = %Trades.TradeExecuted{trade_id: trade_uuid, price: 200, quantity: 2}

      order_binary = GridCodec.encode(order)
      trade_binary = GridCodec.encode(trade)

      {:ok, decoded_order} = GridCodec.decode(order_binary)
      {:ok, decoded_trade} = GridCodec.decode(trade_binary)

      # Correct struct types
      assert %Events.OrderCreated{} = decoded_order
      assert %Trades.TradeExecuted{} = decoded_trade

      # Correct data
      assert decoded_order.order_id == order_uuid
      assert decoded_trade.trade_id == trade_uuid
    end
  end

  describe "batch processing" do
    test "processes stream of mixed events" do
      events = [
        %Events.OrderCreated{order_id: <<1::128>>, price: 100, quantity: 1},
        %Events.OrderFilled{
          order_id: <<1::128>>,
          fill_price: 101,
          fill_quantity: 1,
          timestamp: 1000
        },
        %Events.OrderCreated{order_id: <<2::128>>, price: 200, quantity: 2},
        %Events.OrderCancelled{order_id: <<2::128>>, reason_code: 1}
      ]

      # Encode all events
      binaries = Enum.map(events, &GridCodec.encode/1)

      # Decode and verify
      decoded =
        Enum.map(binaries, fn binary ->
          {:ok, event} = GridCodec.decode(binary)
          event
        end)

      assert length(decoded) == 4
      assert %Events.OrderCreated{} = Enum.at(decoded, 0)
      assert %Events.OrderFilled{} = Enum.at(decoded, 1)
      assert %Events.OrderCreated{} = Enum.at(decoded, 2)
      assert %Events.OrderCancelled{} = Enum.at(decoded, 3)
    end
  end

  describe "zero-copy wrap dispatch" do
    test "wraps different event types correctly" do
      order = %Events.OrderCreated{order_id: <<1::128>>, price: 100, quantity: 5}

      fill = %Events.OrderFilled{
        order_id: <<2::128>>,
        fill_price: 101,
        fill_quantity: 3,
        timestamp: 2000
      }

      order_binary = GridCodec.encode(order)
      fill_binary = GridCodec.encode(fill)

      {:ok, order_env, Events.OrderCreated} = GridCodec.wrap(order_binary)
      {:ok, fill_env, Events.OrderFilled} = GridCodec.wrap(fill_binary)

      # Access fields via envelope
      assert Envelope.get(order_env, :price) == 100
      assert Envelope.get(fill_env, :fill_price) == 101
    end
  end

  describe "introspection" do
    test "each codec has unique template_id" do
      assert Events.OrderCreated.__template_id__() == 1
      assert Events.OrderFilled.__template_id__() == 2
      assert Events.OrderCancelled.__template_id__() == 3
      # same, different schema
      assert Trades.TradeExecuted.__template_id__() == 1
    end

    test "each codec has correct schema_id" do
      assert Events.OrderCreated.__schema_id__() == 900
      assert Events.OrderFilled.__schema_id__() == 900
      assert Events.OrderCancelled.__schema_id__() == 900
      # different schema
      assert Trades.TradeExecuted.__schema_id__() == 901
    end
  end
end
