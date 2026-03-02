# Binary Layout Update Benchmarks
#
# Measures the cost of updating fields in binary layouts vs structs.
# Run from example_app/: mix run ../docs/article/update_benchmarks.exs

defmodule Bench.Msg do
  use GridCodec.Struct, template_id: 80, schema_id: 500

  defcodec do
    field :id, :u64
    field :user_id, :u64
    field :channel_id, :u64
    field :status, :u8
    field :flags, :u8
    field :counter, :u32
    field :price, :u64
    field :quantity, :u32
    field :timestamp, :timestamp_us
    field :extra1, :u64
    field :extra2, :u64
    field :extra3, :u64
    field :extra4, :u64
    field :extra5, :u64
    field :extra6, :u64
    field :extra7, :u64
    field :extra8, :u64
  end
end

defmodule Bench.Updates do
  alias Bench.Msg
  require Msg

  def run do
    now = System.system_time(:microsecond)

    struct = %Msg{
      id: 1, user_id: 42, channel_id: 7, status: 1, flags: 0,
      counter: 0, price: 15_000, quantity: 100, timestamp: now,
      extra1: 0, extra2: 0, extra3: 0, extra4: 0,
      extra5: 0, extra6: 0, extra7: 0, extra8: 0
    }

    bin = Msg.encode(struct)
    {:ok, decoded} = Msg.decode(bin)

    word = :erlang.system_info(:wordsize)
    IO.puts("Msg: #{length(Msg.__fields__())} fields, #{byte_size(bin)} bytes wire, #{:erts_debug.size(decoded) * word} bytes struct heap")
    IO.puts("")

    bench_single_field_update(bin, decoded)
    bench_multi_field_update(bin, decoded)
    bench_update_at_different_offsets(bin, decoded)
    bench_scaling_by_size()
  end

  # --- 1. Single field update ---

  defp bench_single_field_update(bin, decoded) do
    IO.puts("1. Single field update (status: u8 at offset 32)")
    n = 500_000

    # Struct update
    {t_struct, _} = :timer.tc(fn ->
      for _ <- 1..n, do: %{decoded | status: 2}
    end)

    # Binary splice — manual
    status_offset = 8 + 24  # header + id + user_id + channel_id
    {t_splice, _} = :timer.tc(fn ->
      for _ <- 1..n do
        <<before::binary-size(status_offset), _::8, rest::binary>> = bin
        <<before::binary, 2::8, rest::binary>>
      end
    end)

    # Binary full re-encode
    {t_reencode, _} = :timer.tc(fn ->
      for _ <- 1..n do
        {:ok, s} = Msg.decode(bin)
        Msg.encode(%{s | status: 2})
      end
    end)

    IO.puts("   Struct update:       #{Float.round(t_struct / n * 1000, 1)} ns/op")
    IO.puts("   Binary splice:       #{Float.round(t_splice / n * 1000, 1)} ns/op")
    IO.puts("   Decode + re-encode:  #{Float.round(t_reencode / n * 1000, 1)} ns/op")
    IO.puts("   Splice/struct ratio: #{Float.round(t_splice / max(t_struct, 1), 1)}x")
    IO.puts("")
  end

  # --- 2. Multiple field update ---

  defp bench_multi_field_update(bin, decoded) do
    IO.puts("2. Update 3 fields at once (status, flags, counter)")
    n = 500_000

    # Struct: update 3 fields
    {t_struct, _} = :timer.tc(fn ->
      for _ <- 1..n, do: %{decoded | status: 2, flags: 7, counter: 42}
    end)

    # Binary: three-field splice in one pass
    # Fields are adjacent: status(u8) + flags(u8) + counter(u32) = 6 bytes
    status_offset = 8 + 24
    {t_splice, _} = :timer.tc(fn ->
      for _ <- 1..n do
        <<before::binary-size(status_offset), _::8, _::8, _::little-32, rest::binary>> = bin
        <<before::binary, 2::8, 7::8, 42::little-32, rest::binary>>
      end
    end)

    IO.puts("   Struct update 3:     #{Float.round(t_struct / n * 1000, 1)} ns/op")
    IO.puts("   Binary splice 3:     #{Float.round(t_splice / n * 1000, 1)} ns/op")
    IO.puts("   Splice/struct ratio: #{Float.round(t_splice / max(t_struct, 1), 1)}x")
    IO.puts("")
  end

  # --- 3. Update at different offsets ---

  defp bench_update_at_different_offsets(bin, decoded) do
    IO.puts("3. Update cost by field position")
    IO.puts("   Field            Offset  Struct ns  Splice ns  Ratio")
    n = 500_000

    fields = [
      {:status, 8 + 24, 1, fn d -> %{d | status: 2} end},
      {:price, 8 + 30, 8, fn d -> %{d | price: 99} end},
      {:extra8, 8 + 30 + 8 + 4 + 8 + 56, 8, fn d -> %{d | extra8: 99} end}
    ]

    for {name, offset, size, struct_fn} <- fields do
      {t_struct, _} = :timer.tc(fn ->
        for _ <- 1..n, do: struct_fn.(decoded)
      end)

      {t_splice, _} = :timer.tc(fn ->
        for _ <- 1..n do
          <<before::binary-size(offset), _::binary-size(size), rest::binary>> = bin
          new_val = case size do
            1 -> <<2::8>>
            8 -> <<99::little-64>>
          end
          <<before::binary, new_val::binary, rest::binary>>
        end
      end)

      struct_ns = Float.round(t_struct / n * 1000, 1)
      splice_ns = Float.round(t_splice / n * 1000, 1)
      ratio = Float.round(t_splice / max(t_struct, 1), 1)
      IO.puts("   #{String.pad_trailing(to_string(name), 16)} #{String.pad_leading(to_string(offset), 6)}  #{String.pad_leading(to_string(struct_ns), 9)}  #{String.pad_leading(to_string(splice_ns), 9)}  #{ratio}x")
    end

    IO.puts("")
  end

  # --- 4. How update cost scales with binary size ---

  defp bench_scaling_by_size do
    IO.puts("4. Update cost scaling by binary size")
    IO.puts("   Size (B)  Struct ns  Splice ns  Ratio")
    n = 200_000

    for num_extra <- [0, 4, 8, 16, 32] do
      # Build a struct with varying number of u64 fields
      # We simulate this with raw binaries of different sizes
      payload_size = 32 + num_extra * 8  # base fields + extra u64s
      total_size = 8 + payload_size  # + header

      # Create a binary of the right size
      bin = <<0::size(total_size * 8)>>

      # Create a map with the same number of fields
      struct = Map.new(1..(4 + num_extra), fn i -> {:"f#{i}", 0} end)

      # Update the first field
      {t_struct, _} = :timer.tc(fn ->
        for _ <- 1..n, do: Map.put(struct, :f1, 42)
      end)

      # Splice at offset 8 (rest header), 8 bytes
      {t_splice, _} = :timer.tc(fn ->
        for _ <- 1..n do
          <<before::binary-size(8), _::binary-size(8), rest::binary>> = bin
          <<before::binary, 42::little-64, rest::binary>>
        end
      end)

      struct_ns = Float.round(t_struct / n * 1000, 1)
      splice_ns = Float.round(t_splice / n * 1000, 1)
      ratio = Float.round(t_splice / max(t_struct, 1), 1)
      IO.puts("   #{String.pad_leading(to_string(total_size), 8)}  #{String.pad_leading(to_string(struct_ns), 9)}  #{String.pad_leading(to_string(splice_ns), 9)}  #{ratio}x")
    end

    IO.puts("")
    IO.puts("Note: binary splice always copies the full binary.")
    IO.puts("Struct update may be in-place (OTP 27+ destructive tuple update)")
    IO.puts("if the struct has a single reference.")
    IO.puts("")
    IO.puts("A native layout update could use the same alias analysis to")
    IO.puts("write directly to the byte at the field offset — O(1) regardless")
    IO.puts("of binary size, if the binary is unique (refcount=1).")
  end
end

Bench.Updates.run()
