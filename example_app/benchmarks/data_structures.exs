defmodule Bench.DataStructures do
  @moduledoc """
  Parameterized data structures for benchmarks (small, medium, large).

  These provide realistic, scalable test data for performance analysis.

  Note: Uses integer timestamps (System.system_time/1) instead of DateTime
  structs for optimal encode performance. See AGENTS.md for details on
  DateTime overhead.
  """

  # ============================================================================
  # Small Data Structure (3 fixed fields, no variable fields)
  # ============================================================================

  defmodule SmallOrder do
    use GridCodec.Struct, template_id: 101, schema_id: 200

    defcodec do
      field :order_id, :u64
      field :price, :u64
      field :quantity, :u32
    end
  end

  def small_data do
    %SmallOrder{
      order_id: 12_345_678_901_234_567,
      price: 15_000_000_000,
      quantity: 100_000
    }
  end

  # ============================================================================
  # Medium Data Structure (7 fixed fields, 1 variable field)
  # ============================================================================

  defmodule MediumOrder do
    use GridCodec.Struct, template_id: 102, schema_id: 200

    defcodec do
      field :order_id, :uuid
      field :user_id, :u64
      field :price, :u64
      field :quantity, :u32
      field :side, :u8
      field :timestamp, :timestamp_us
      field :flags, :u8
      field :symbol, :string16
    end
  end

  def medium_data do
    %MediumOrder{
      order_id: :crypto.strong_rand_bytes(16),
      user_id: 12_345_678_901_234_567,
      price: 15_000_000_000,
      quantity: 100_000,
      side: 1,
      # Use integer timestamp for optimal performance
      timestamp: System.system_time(:microsecond),
      flags: 7,
      # 10 char symbol
      symbol: String.duplicate("A", 10)
    }
  end

  # ============================================================================
  # Large Data Structure (15 fixed fields, 3 variable fields)
  # ============================================================================

  defmodule LargeOrder do
    use GridCodec.Struct, template_id: 103, schema_id: 200

    defcodec do
      field :order_id, :uuid
      field :user_id, :u64
      field :account_id, :u64
      field :price, :u64
      field :quantity, :u32
      field :filled_quantity, :u32
      field :side, :u8
      field :order_type, :u8
      field :time_in_force, :u8
      field :timestamp, :timestamp_us
      field :expiry_time, :timestamp_us
      field :flags, :u8
      field :priority, :u8
      field :reserved1, :u32
      field :reserved2, :u64
      field :symbol, :string16
      field :client_order_id, :string32
      field :notes, :string16
    end
  end

  def large_data do
    now = System.system_time(:microsecond)

    %LargeOrder{
      order_id: :crypto.strong_rand_bytes(16),
      user_id: 12_345_678_901_234_567,
      account_id: 98_765_432_109_876_543,
      price: 15_000_000_000,
      quantity: 100_000,
      filled_quantity: 50_000,
      side: 1,
      order_type: 2,
      time_in_force: 1,
      # Use integer timestamps for optimal performance
      timestamp: now,
      # +1 day in microseconds
      expiry_time: now + 86_400_000_000,
      flags: 7,
      priority: 5,
      reserved1: 0,
      reserved2: 0,
      # 10 chars
      symbol: String.duplicate("BTCUSD", 2),
      # 42 chars
      client_order_id: String.duplicate("CLIENT-", 7),
      # 16 chars
      notes: String.duplicate("NOTE", 4)
    }
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Get data structure and codec module for a given size.
  """
  def get_for_size(:small) do
    {small_data(), SmallOrder}
  end

  def get_for_size(:medium) do
    {medium_data(), MediumOrder}
  end

  def get_for_size(:large) do
    {large_data(), LargeOrder}
  end

  @doc """
  Get binary size for a data structure.
  """
  def binary_size(:small) do
    data = small_data()
    byte_size(SmallOrder.encode(data))
  end

  def binary_size(:medium) do
    data = medium_data()
    byte_size(MediumOrder.encode(data))
  end

  def binary_size(:large) do
    data = large_data()
    byte_size(LargeOrder.encode(data))
  end

  @doc """
  Get all sizes for iteration.
  """
  def all_sizes, do: [:small, :medium, :large]
end
