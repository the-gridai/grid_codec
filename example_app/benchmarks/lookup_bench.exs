# Typed Groups & Lookups Benchmark
#
# Compares generated lookup helpers against manual `to_list |> Map.new` /
# `to_list |> Enum.filter` pipelines.
#
# Run with: MIX_ENV=prod mix run benchmarks/lookup_bench.exs

defmodule LookupBench do
  alias ExampleApp.Views.{CommandEnvelope, CurrencyAccount, Fixtures}

  def run do
    IO.puts("Typed Groups & Lookups Benchmark")
    IO.puts("==================================\n")
    IO.puts("This benchmark compares generated lookup helpers against manual lookup")
    IO.puts("construction. Group lookups use compile-time generated reducers that")
    IO.puts("walk the group payload directly instead of materializing `to_list/1`")
    IO.puts("first. Batch lookups are still built on top of batch streaming, so the")
    IO.puts("benchmark shows where further specialization would pay off.\n")

    account = Fixtures.account(12_000)
    {:ok, account_binary} = CurrencyAccount.encode(account)
    {:ok, decoded_account} = CurrencyAccount.decode(account_binary)
    reservations_group = decoded_account.reservations
    reservations_list = GridCodec.Group.to_list(reservations_group)

    envelope = Fixtures.command_envelope(12_000)
    {:ok, envelope_binary} = CommandEnvelope.encode(envelope)
    {:ok, decoded_envelope} = CommandEnvelope.decode(envelope_binary)
    commands_batch = decoded_envelope.commands
    commands_list = GridCodec.Batch.to_list(commands_batch)

    IO.puts("Account wire size: #{byte_size(account_binary)} bytes")
    IO.puts("Envelope wire size: #{byte_size(envelope_binary)} bytes\n")

    run_group_map_bench(decoded_account, reservations_group, reservations_list)
    run_group_filter_bench(decoded_account, reservations_group, reservations_list)
    run_batch_map_bench(decoded_envelope, commands_batch, commands_list)
  end

  defp run_group_map_bench(decoded_account, reservations_group, reservations_list) do
    IO.puts("--- Group: reservations_by_id ---\n")

    Benchee.run(
      %{
        "generated lookup (group -> map)" => fn ->
          {:ok, _lookup} = CurrencyAccount.reservations_by_id(decoded_account)
        end,
        "manual Group.to_list |> Map.new" => fn ->
          reservations_group
          |> GridCodec.Group.to_list()
          |> Map.new(&{&1.reservation_id, &1})
        end,
        "predecoded list |> Map.new" => fn ->
          Map.new(reservations_list, &{&1.reservation_id, &1})
        end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )
  end

  defp run_group_filter_bench(decoded_account, reservations_group, reservations_list) do
    IO.puts("\n--- Group: active_reservations ---\n")

    Benchee.run(
      %{
        "generated lookup (group -> list)" => fn ->
          {:ok, _lookup} = CurrencyAccount.active_reservations(decoded_account)
        end,
        "manual Group.to_list |> Enum.filter" => fn ->
          reservations_group
          |> GridCodec.Group.to_list()
          |> Enum.filter(& &1.active)
        end,
        "predecoded list |> Enum.filter" => fn ->
          Enum.filter(reservations_list, & &1.active)
        end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )
  end

  defp run_batch_map_bench(decoded_envelope, commands_batch, commands_list) do
    IO.puts("\n--- Batch: commands_by_reservation_id ---\n")

    Benchee.run(
      %{
        "generated lookup (batch -> map)" => fn ->
          {:ok, _lookup} = CommandEnvelope.commands_by_reservation_id(decoded_envelope)
        end,
        "manual Batch.to_list |> Map.new" => fn ->
          commands_batch
          |> GridCodec.Batch.to_list()
          |> Map.new(fn {_seq, _tag, command} -> {command.reservation_id, command} end)
        end,
        "predecoded list |> Map.new" => fn ->
          Map.new(commands_list, fn {_seq, _tag, command} -> {command.reservation_id, command} end)
        end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )
  end
end

LookupBench.run()
