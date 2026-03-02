# Binary Layouts: Benchmarks
#
# Run from example_app/:
#   mix run ../docs/article/benchmarks.exs

defmodule Bench.ChatMessage do
  use GridCodec.Struct, template_id: 70, schema_id: 400

  defcodec do
    field :message_id, :u64
    field :channel_id, :u64
    field :guild_id, :u64
    field :author_id, :u64
    field :parent_id, :u64
    field :nonce, :u64
    field :content_length, :u32
    field :content_hash, :u64
    field :message_type, :u8
    field :author_type, :u8
    field :model_id, :u16
    field :prompt_tokens, :u32
    field :completion_tokens, :u32
    field :temperature_x1k, :u32
    field :top_p_x1k, :u32
    field :max_tokens, :u32
    field :latency_first_ms, :u32
    field :latency_total_ms, :u32
    field :cost_micros, :u64
    field :rate_remaining, :u32
    field :rate_reset_ms, :u32
    field :status, :u8
    field :flags, :u16
    field :edit_count, :u8
    field :reply_count, :u32
    field :thread_id, :u64
    field :created_at, :timestamp_us
    field :edited_at, :timestamp_us
  end
end

defmodule Bench.Run do
  alias Bench.ChatMessage
  require ChatMessage

  def run do
    now = System.system_time(:microsecond)

    chat = %ChatMessage{
      message_id: 99_001, channel_id: 42, guild_id: 1, author_id: 7,
      parent_id: 0, nonce: 12345, content_length: 256, content_hash: 0xDEADBEEF,
      message_type: 1, author_type: 2, model_id: 3,
      prompt_tokens: 150, completion_tokens: 80,
      temperature_x1k: 700, top_p_x1k: 950, max_tokens: 4096,
      latency_first_ms: 45, latency_total_ms: 1200, cost_micros: 3500,
      rate_remaining: 88, rate_reset_ms: 60_000,
      status: 2, flags: 1, edit_count: 0, reply_count: 3, thread_id: 0,
      created_at: now, edited_at: now
    }

    bin = ChatMessage.encode(chat)
    {:ok, decoded} = ChatMessage.decode(bin)
    word = :erlang.system_info(:wordsize)

    IO.puts("Codec: #{length(ChatMessage.__fields__())} fields")
    IO.puts("  Wire:   #{byte_size(bin)} B")
    IO.puts("  Heap:   binary=#{:erts_debug.size(bin) * word} B  struct=#{:erts_debug.size(decoded) * word} B")
    IO.puts("  ETF:    binary=#{byte_size(:erlang.term_to_binary(bin))} B  struct=#{byte_size(:erlang.term_to_binary(decoded))} B")
    IO.puts("")

    bench_send(bin, decoded)
    bench_etf(bin, decoded)
    bench_rejection(chat, bin, decoded)
    bench_selective(bin, decoded)
  end

  # --- 1. Cross-process send ---
  # Each process receives M copies of the message and holds them all.
  # This makes message data dominate per-process overhead.

  defp bench_send(bin, decoded) do
    IO.puts("1. send/2 — receiver heap (100 receivers × 50 messages each)")
    IO.puts("   Messages/proc  Binary KB   Struct KB   Ratio")

    n_procs = 100

    measure = fn msg, msgs_per_proc ->
      parent = self()
      pids = Enum.map(1..n_procs, fn _ ->
        spawn(fn ->
          msgs = for _ <- 1..msgs_per_proc do
            receive do m -> m end
          end
          :erlang.garbage_collect()
          {_, mem} = :erlang.process_info(self(), :memory)
          send(parent, {:mem, mem})
          receive do :stop -> msgs end
        end)
      end)

      for _ <- 1..msgs_per_proc do
        Enum.each(pids, fn pid -> send(pid, msg) end)
      end

      heaps = for _ <- 1..n_procs, do: receive(do: ({:mem, m} -> m))
      Enum.each(pids, fn pid -> send(pid, :stop) end)
      Enum.sum(heaps)
    end

    # Warm up
    measure.(bin, 1)
    measure.(decoded, 1)

    for m <- [1, 10, 50] do
      b = measure.(bin, m)
      s = measure.(decoded, m)
      ratio = Float.round(s / max(b, 1), 1)
      IO.puts("   #{String.pad_leading(to_string(m), 13)}  #{String.pad_leading(Float.round(b/1024, 1) |> to_string(), 9)}  #{String.pad_leading(Float.round(s/1024, 1) |> to_string(), 10)}   #{ratio}x")
    end

    IO.puts("")
  end

  # --- 2. ETF serialization ---

  defp bench_etf(bin, decoded) do
    etf_bin = :erlang.term_to_binary(bin)
    etf_str = :erlang.term_to_binary(decoded)
    n = 200_000

    {ser_bin, _} = :timer.tc(fn -> for _ <- 1..n, do: :erlang.term_to_binary(bin) end)
    {ser_str, _} = :timer.tc(fn -> for _ <- 1..n, do: :erlang.term_to_binary(decoded) end)
    {des_bin, _} = :timer.tc(fn -> for _ <- 1..n, do: :erlang.binary_to_term(etf_bin) end)
    {des_str, _} = :timer.tc(fn -> for _ <- 1..n, do: :erlang.binary_to_term(etf_str) end)

    IO.puts("2. ETF serialization (#{n} iterations)")
    IO.puts("   Wire size:    binary=#{byte_size(etf_bin)} B   struct=#{byte_size(etf_str)} B   (#{Float.round(byte_size(etf_str) / byte_size(etf_bin), 1)}x)")
    IO.puts("   Serialize:    binary=#{div(ser_bin, 1000)} ms   struct=#{div(ser_str, 1000)} ms   (#{Float.round(ser_str / max(ser_bin, 1), 1)}x)")
    IO.puts("   Deserialize:  binary=#{div(des_bin, 1000)} ms   struct=#{div(des_str, 1000)} ms   (#{Float.round(des_str / max(des_bin, 1), 1)}x)")
    IO.puts("")
  end

  # --- 3. Early rejection ---

  defp bench_rejection(chat, _bin, decoded) do
    batch = Enum.map(1..1000, fn i ->
      msg = cond do
        rem(i, 10) < 3 -> %{chat | message_id: i, rate_remaining: 0}
        rem(i, 10) < 5 -> %{chat | message_id: i, flags: 0, author_type: 1}
        rem(i, 10) < 7 -> %{chat | message_id: i, content_length: 99_000_000}
        true           -> %{chat | message_id: i}
      end
      ChatMessage.encode(msg)
    end)

    struct_filter = fn b ->
      {:ok, s} = ChatMessage.decode(b)
      s.rate_remaining > 0 and (s.flags > 0 or s.author_type == 2) and
        s.content_length < 10_000_000 and s.message_type in [1, 2, 3, 4]
    end

    layout_filter = fn b ->
      case b do
        ChatMessage.match(rate_remaining: r, flags: f, author_type: at,
                          content_length: cl, message_type: mt)
        when r > 0 and (f > 0 or at == 2) and cl < 10_000_000 and mt in [1, 2, 3, 4] -> true
        _ -> false
      end
    end

    survivors = Enum.count(batch, layout_filter)
    word = :erlang.system_info(:wordsize)
    decode_cost = :erts_debug.size(decoded) * word

    {t_struct, _} = :timer.tc(fn -> Enum.each(batch, struct_filter) end)
    {t_layout, _} = :timer.tc(fn -> Enum.each(batch, layout_filter) end)

    IO.puts("3. Early rejection — 1000 messages, #{survivors} pass, #{1000 - survivors} rejected")
    IO.puts("   Struct (decode all):    #{Float.round(t_struct / 1000, 2)} ms   (1000 decodes × #{decode_cost} B = #{div(1000 * decode_cost, 1024)} KB)")
    IO.puts("   Layout (filter binary): #{Float.round(t_layout / 1000, 2)} ms   (0 decodes)")
    IO.puts("   Speedup: #{Float.round(t_struct / max(t_layout, 1), 1)}x")
    IO.puts("")
  end

  # --- 4. Selective access ---

  defp bench_selective(bin, decoded) do
    n = 500_000

    layout_read = fn ->
      case bin do
        ChatMessage.match(channel_id: ch, flags: f) -> {ch, f}
      end
    end

    decode_read = fn ->
      {:ok, s} = ChatMessage.decode(bin)
      {s.channel_id, s.flags}
    end

    pre_read = fn -> {decoded.channel_id, decoded.flags} end

    {t_layout, _} = :timer.tc(fn -> for _ <- 1..n, do: layout_read.() end)
    {t_decode, _} = :timer.tc(fn -> for _ <- 1..n, do: decode_read.() end)
    {t_pre, _} = :timer.tc(fn -> for _ <- 1..n, do: pre_read.() end)

    IO.puts("4. Selective access — read 2 of 28 fields (#{n} iterations)")
    IO.puts("   Layout match:         #{Float.round(t_layout / n * 1000, 1)} ns/op")
    IO.puts("   Pre-decoded lookup:   #{Float.round(t_pre / n * 1000, 1)} ns/op")
    IO.puts("   Decode all, read 2:   #{Float.round(t_decode / n * 1000, 1)} ns/op")
    IO.puts("   Layout vs decode-first: #{Float.round(t_decode / max(t_layout, 1), 1)}x")
    IO.puts("")
  end
end

Bench.Run.run()
