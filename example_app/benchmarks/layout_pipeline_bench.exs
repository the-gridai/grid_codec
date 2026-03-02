# AgentChat Binary Layout Benchmarks
#
# Run with: mix run benchmarks/layout_pipeline_bench.exs
#
# Three honest claims:
# 1. Don't decode what you're going to reject.
# 2. Don't copy what you can share.
# 3. Don't allocate what you won't use.

defmodule Bench.AC.ChatMessage do
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

defmodule Bench.AC.TypingEvent do
  use GridCodec.Struct, template_id: 71, schema_id: 400
  defcodec do
    field :channel_id, :u64
    field :user_id, :u64
    field :timestamp, :timestamp_us
    field :is_agent, :u8
  end
end

defmodule Bench.AC.ReactionEvent do
  use GridCodec.Struct, template_id: 72, schema_id: 400
  defcodec do
    field :message_id, :u64
    field :channel_id, :u64
    field :user_id, :u64
    field :emoji_id, :u32
    field :timestamp, :timestamp_us
    field :action, :u8
  end
end

defmodule Bench.AgentChat do
  alias Bench.AC.{ChatMessage, TypingEvent, ReactionEvent}

  require ChatMessage
  require TypingEvent
  require ReactionEvent

  defmacrop chat(fields), do: quote(do: ChatMessage.match(unquote(fields)))
  defmacrop typing(fields), do: quote(do: TypingEvent.match(unquote(fields)))
  defmacrop reaction(fields), do: quote(do: ReactionEvent.match(unquote(fields)))

  # -- Struct stages --

  defp struct_rate_check(%ChatMessage{rate_remaining: r}) when r > 0, do: true
  defp struct_rate_check(_), do: false

  defp struct_perm_check(%ChatMessage{flags: f, author_type: at}) when f > 0 or at == 2, do: true
  defp struct_perm_check(_), do: false

  defp struct_validate(%ChatMessage{content_length: cl, message_type: mt})
       when cl < 10_000_000 and mt in [1, 2, 3, 4], do: true
  defp struct_validate(_), do: false

  defp struct_route(%ChatMessage{channel_id: ch, message_type: mt}), do: {ch, mt}

  # -- Layout stages --

  defp layout_rate_check(chat(rate_remaining: r)) when r > 0, do: true
  defp layout_rate_check(_), do: false

  defp layout_perm_check(chat(flags: f, author_type: at)) when f > 0 or at == 2, do: true
  defp layout_perm_check(_), do: false

  defp layout_validate(chat(content_length: cl, message_type: mt))
       when cl < 10_000_000 and mt in [1, 2, 3, 4], do: true
  defp layout_validate(_), do: false

  defp layout_route(chat(channel_id: ch, message_type: mt)), do: {ch, mt}
  defp layout_notify(chat(channel_id: ch, flags: f)), do: {ch, f}

  defp get_chat_author(chat(author_id: a)), do: a
  defp get_typing_user(typing(user_id: u)), do: u
  defp get_reaction_user(reaction(user_id: u)), do: u

  # ============================================================================

  def run do
    now = System.system_time(:microsecond)

    chat_struct = %ChatMessage{
      message_id: 99_001, channel_id: 42, guild_id: 1,
      author_id: 7, parent_id: 0, nonce: 12345,
      content_length: 256, content_hash: 0xDEADBEEF,
      message_type: 1, author_type: 2, model_id: 3,
      prompt_tokens: 150, completion_tokens: 80,
      temperature_x1k: 700, top_p_x1k: 950, max_tokens: 4096,
      latency_first_ms: 45, latency_total_ms: 1200,
      cost_micros: 3500, rate_remaining: 88, rate_reset_ms: 60_000,
      status: 2, flags: 1, edit_count: 0, reply_count: 3,
      thread_id: 0, created_at: now, edited_at: now
    }

    chat_binary = ChatMessage.encode(chat_struct)
    {:ok, chat_decoded} = ChatMessage.decode(chat_binary)

    word = :erlang.system_info(:wordsize)

    IO.puts("""
    ╔══════════════════════════════════════════════════════════════════════╗
    ║            AgentChat — Binary Layout Benchmarks                    ║
    ╠══════════════════════════════════════════════════════════════════════╣
    ║  ChatMessage: #{byte_size(chat_binary)}B wire, #{:erts_debug.size(chat_decoded) * word}B struct heap, #{length(ChatMessage.__fields__())} fields        ║
    ║                                                                    ║
    ║  1. Don't decode what you're going to reject                       ║
    ║  2. Don't copy what you can share                                  ║
    ║  3. Don't allocate what you won't use                              ║
    ╚══════════════════════════════════════════════════════════════════════╝
    """)

    bench_early_rejection(chat_struct)
    bench_cross_process(chat_struct, chat_binary)
    bench_serialization(chat_struct, chat_binary)
    bench_selective(chat_binary, chat_decoded)
    bench_dispatch(chat_struct)
    bench_memory(chat_struct)
  end

  # ============================================================================
  # Claim 1
  # ============================================================================

  defp bench_early_rejection(chat_struct) do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("CLAIM 1: Don't Decode What You're Going to Reject")
    IO.puts(String.duplicate("═", 70))
    IO.puts("  Agent message burst: 1000 messages, ~70% rate-limited\n")

    batch = Enum.map(1..1000, fn i ->
      msg = cond do
        rem(i, 10) < 3 -> %{chat_struct | message_id: i, rate_remaining: 0}
        rem(i, 10) < 5 -> %{chat_struct | message_id: i, flags: 0, author_type: 1}
        rem(i, 10) < 7 -> %{chat_struct | message_id: i, content_length: 99_000_000}
        true           -> %{chat_struct | message_id: i}
      end
      ChatMessage.encode(msg)
    end)

    Benchee.run(
      %{
        "struct: decode ALL then filter" => {
          fn bin ->
            {:ok, s} = ChatMessage.decode(bin)
            with true <- struct_rate_check(s),
                 true <- struct_perm_check(s),
                 true <- struct_validate(s) do
              {:ok, struct_route(s)}
            else
              false -> :rejected
            end
          end,
          before_each: fn _ -> Enum.random(batch) end
        },
        "layout: filter binary, decode survivors" => {
          fn bin ->
            with true <- layout_rate_check(bin),
                 true <- layout_perm_check(bin),
                 true <- layout_validate(bin) do
              {:ok, s} = ChatMessage.decode(bin)
              {:ok, struct_route(s)}
            else
              false -> :rejected
            end
          end,
          before_each: fn _ -> Enum.random(batch) end
        },
        "layout: full zero-copy (no decode)" => {
          fn bin ->
            with true <- layout_rate_check(bin),
                 true <- layout_perm_check(bin),
                 true <- layout_validate(bin) do
              {:ok, layout_route(bin)}
            else
              false -> :rejected
            end
          end,
          before_each: fn _ -> Enum.random(batch) end
        }
      },
      warmup: 2,
      time: 5,
      memory_time: 2,
      print: [configuration: false, fast_warning: false]
    )
  end

  # ============================================================================
  # Claim 2
  # ============================================================================

  defp bench_cross_process(chat_struct, chat_binary) do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("CLAIM 2: Don't Copy What You Can Share (local node)")
    IO.puts(String.duplicate("═", 70))
    IO.puts("  PubSub broadcast of 148B ChatMessage to N subscribers\n")

    measure_send(chat_binary, 10)
    measure_send(chat_struct, 10)

    for n <- [10, 100, 500] do
      bin_us = measure_send(chat_binary, n)
      str_us = measure_send(chat_struct, n)
      ratio = Float.round(str_us / max(bin_us, 1), 1)
      IO.puts("  N=#{String.pad_leading(to_string(n), 4)}  binary: #{String.pad_leading(to_string(bin_us), 6)}μs  struct: #{String.pad_leading(to_string(str_us), 6)}μs  (#{ratio}x)")
    end

    IO.puts("")
  end

  defp measure_send(msg, n) do
    parent = self()
    pids = Enum.map(1..n, fn _ ->
      spawn(fn ->
        receive do _msg -> :ok end
        send(parent, :done)
      end)
    end)

    {us, _} = :timer.tc(fn ->
      Enum.each(pids, fn pid -> send(pid, msg) end)
    end)

    for _ <- 1..n, do: receive(do: (:done -> :ok))
    us
  end

  defp bench_serialization(chat_struct, chat_binary) do
    IO.puts(String.duplicate("─", 70))
    IO.puts("CLAIM 2b: Distributed Send — ETF Serialization Cost")
    IO.puts(String.duplicate("─", 70))

    etf_s = :erlang.term_to_binary(chat_struct)
    etf_b = :erlang.term_to_binary(chat_binary)

    IO.puts("  ETF wire: struct=#{byte_size(etf_s)}B  binary=#{byte_size(etf_b)}B  (#{Float.round(byte_size(etf_s) / byte_size(etf_b), 1)}x)")

    {s_us, _} = :timer.tc(fn -> for _ <- 1..100_000, do: :erlang.term_to_binary(chat_struct) end)
    {b_us, _} = :timer.tc(fn -> for _ <- 1..100_000, do: :erlang.term_to_binary(chat_binary) end)

    IO.puts("  Serialize 100K: struct=#{div(s_us, 1000)}ms  binary=#{div(b_us, 1000)}ms  (#{Float.round(s_us / max(b_us, 1), 1)}x)\n")
  end

  # ============================================================================
  # Claim 3
  # ============================================================================

  defp bench_selective(chat_binary, chat_decoded) do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("CLAIM 3: Don't Allocate What You Won't Use — Selective Access")
    IO.puts(String.duplicate("═", 70))
    IO.puts("  Notification system needs 2 of 28 fields\n")

    Benchee.run(
      %{
        "struct: decode all 28, read 2" => {
          fn bin ->
            {:ok, s} = ChatMessage.decode(bin)
            {s.channel_id, s.flags}
          end,
          before_each: fn _ -> chat_binary end
        },
        "struct: pre-decoded, read 2" => fn ->
          {chat_decoded.channel_id, chat_decoded.flags}
        end,
        "layout: match 2 of 28 fields" => {
          fn bin -> layout_notify(bin) end,
          before_each: fn _ -> chat_binary end
        }
      },
      warmup: 2,
      time: 5,
      memory_time: 2,
      print: [configuration: false, fast_warning: false]
    )
  end

  defp bench_dispatch(chat_struct) do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("CLAIM 3: Don't Allocate What You Won't Use — Dispatch by Header")
    IO.puts(String.duplicate("═", 70))
    IO.puts("  1000 mixed Chat/Typing/Reaction events\n")

    now = System.system_time(:microsecond)

    messages = Enum.map(1..1000, fn i ->
      case rem(i, 3) do
        0 -> ChatMessage.encode(chat_struct)
        1 -> TypingEvent.encode(%TypingEvent{channel_id: 42, user_id: 7, timestamp: now, is_agent: 1})
        2 -> ReactionEvent.encode(%ReactionEvent{message_id: 99_001, channel_id: 42, user_id: 3,
               emoji_id: 0x1F525, timestamp: now, action: 1})
      end
    end)

    Benchee.run(
      %{
        "struct: full decode + pattern match" => {
          fn bin ->
            case GridCodec.decode(bin) do
              {:ok, %ChatMessage{author_id: a}} -> {:chat, a}
              {:ok, %TypingEvent{user_id: u}} -> {:typing, u}
              {:ok, %ReactionEvent{user_id: u}} -> {:reaction, u}
            end
          end,
          before_each: fn _ -> Enum.random(messages) end
        },
        "layout: header dispatch + 1 field" => {
          fn bin ->
            {:ok, h, _} = GridCodec.Header.decode(bin)
            case h.template_id do
              70 -> {:chat, get_chat_author(bin)}
              71 -> {:typing, get_typing_user(bin)}
              72 -> {:reaction, get_reaction_user(bin)}
            end
          end,
          before_each: fn _ -> Enum.random(messages) end
        }
      },
      warmup: 2,
      time: 5,
      memory_time: 2,
      print: [configuration: false, fast_warning: false]
    )
  end

  defp bench_memory(chat_struct) do
    IO.puts("\n" <> String.duplicate("═", 70))
    IO.puts("BUFFER: 1000 ChatMessages in GenServer State")
    IO.puts(String.duplicate("═", 70))

    binaries = Enum.map(1..1000, fn _ -> ChatMessage.encode(chat_struct) end)
    structs = Enum.map(binaries, fn bin -> {:ok, s} = ChatMessage.decode(bin); s end)

    word = :erlang.system_info(:wordsize)
    b = :erts_debug.size(binaries) * word
    s = :erts_debug.size(structs) * word

    IO.puts("  Binary list:  #{b} bytes (#{div(b, 1024)} KB)")
    IO.puts("  Struct list:  #{s} bytes (#{div(s, 1024)} KB)")
    IO.puts("  Ratio:        #{Float.round(s / b, 1)}x more for structs\n")
  end
end

Bench.AgentChat.run()
