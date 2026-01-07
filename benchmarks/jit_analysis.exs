defmodule Bench.JITAnalysis do
  @moduledoc """
  JIT (BeamAsm) analysis for GridCodec.Struct.

  Analyzes:
  - JIT compilation status
  - Hot function identification
  - Inlining opportunities
  - Native code generation
  """

  defmodule TestOrder do
    use GridCodec.Struct, template_id: 1, schema_id: 100

    defcodec do
      field :order_id, :uuid
      field :user_id, :u64
      field :price, :u64
      field :quantity, :u32
      field :side, :u8
      field :timestamp, :timestamp_us
      field :flags, :u8
    end
  end

  def run do
    IO.puts("""
    ════════════════════════════════════════════════════════════════════════════
    JIT (BeamAsm) ANALYSIS
    ════════════════════════════════════════════════════════════════════════════
    """)

    # Check JIT availability
    jit_available = check_jit_available()
    IO.puts("JIT (BeamAsm) available: #{jit_available}")

    if jit_available do
      IO.puts("\n── Analyzing JIT compilation status ────────────────────────────────")
      analyze_jit_status()

      IO.puts("\n── Warming up functions for JIT ─────────────────────────────────────")
      warmup_functions()

      IO.puts("\n── Checking JIT compilation after warmup ───────────────────────────")
      analyze_jit_status()

      IO.puts("\n── Analyzing hot paths ────────────────────────────────────────────")
      analyze_hot_paths()
    else
      IO.puts("\n⚠ JIT not available - running in interpreted mode")
      IO.puts("  Consider using OTP 24+ with JIT enabled")
    end

    IO.puts("\n── Bytecode analysis ────────────────────────────────────────────────")
    analyze_bytecode()

    IO.puts("\n" <> String.duplicate("═", 80))
    IO.puts("JIT ANALYSIS COMPLETE")
    IO.puts(String.duplicate("═", 80))
  end

  defp check_jit_available do
    case :erlang.system_info(:emu_flavor) do
      :jit -> true
      _ -> false
    end
  end

  defp analyze_jit_status do
    # Check if functions are JIT compiled
    functions = [
      {TestOrder, :encode, 1},
      {TestOrder, :decode, 1},
      {TestOrder, :get, 2}
    ]

    for {module, function, arity} <- functions do
      case :code.get_object_code(module) do
        {^module, beam, _filename} ->
          # Check if function exists and is compiled
          case :beam_disasm.file(beam) do
            {:beam_file, _, _, _, _, code} ->
              fn_code = Enum.find(code, fn
                {:function, ^function, ^arity, _, _} -> true
                _ -> false
              end)

              case fn_code do
                {:function, _, _, _, instructions} ->
                  instruction_count = length(instructions)
                  IO.puts("  #{inspect(module)}.#{function}/#{arity}:")
                  IO.puts("    Instructions: #{instruction_count}")
                  IO.puts("    Status: Compiled (JIT status unknown from bytecode)")

                nil ->
                  IO.puts("  #{inspect(module)}.#{function}/#{arity}: Not found")
              end

            _ ->
              IO.puts("  #{inspect(module)}.#{function}/#{arity}: Could not disassemble")
          end

        _ ->
          IO.puts("  #{inspect(module)}.#{function}/#{arity}: Module not loaded")
      end
    end
  end

  defp warmup_functions do
    order_id = :crypto.strong_rand_bytes(16)
    timestamp = DateTime.utc_now()

    order = %TestOrder{
      order_id: order_id,
      user_id: 12_345_678_901_234_567,
      price: 15_000_000_000,
      quantity: 100_000,
      side: 1,
      timestamp: timestamp,
      flags: 7
    }

    # Warm up encode
    for _i <- 1..100_000 do
      TestOrder.encode(order)
    end

    binary = TestOrder.encode(order)

    # Warm up decode
    for _i <- 1..100_000 do
      TestOrder.decode(binary)
    end

    # Warm up get
    case TestOrder.wrap(binary) do
      {:ok, env} ->
        for _i <- 1..100_000 do
          TestOrder.get(env, :price)
        end
      _ ->
        :ok
    end

    IO.puts("  ✓ Functions warmed up (100K iterations each)")
  end

  defp analyze_hot_paths do
    IO.puts("""
    Hot path analysis recommendations:

    1. Use :recon library to identify hot functions:
       :recon.hot(100)  # Top 100 functions by call count

    2. Check function call counts:
       :recon.info(TestOrder, :encode, 1)

    3. Monitor with :observer:
       :observer.start()
       # Navigate to "Load Charts" -> "Function Calls"

    4. Use perf/instruments for C-level hot path analysis:
       perf record -g mix run benchmarks/c_level_profiling.exs
       perf report
    """)
  end

  defp analyze_bytecode do
    case :code.get_object_code(TestOrder) do
      {TestOrder, beam, _filename} ->
        {:beam_file, _, _, _, _, code} = :beam_disasm.file(beam)

        encode_fn = Enum.find(code, fn
          {:function, :encode, 1, _, _} -> true
          _ -> false
        end)

        decode_fn = Enum.find(code, fn
          {:function, :decode, 1, _, _} -> true
          _ -> false
        end)

        IO.puts("  Encode/1:")
        case encode_fn do
          {:function, _, _, _, instructions} ->
            IO.puts("    Total instructions: #{length(instructions)}")
            analyze_instructions(instructions)

          _ ->
            IO.puts("    Function not found")
        end

        IO.puts("\n  Decode/1:")
        case decode_fn do
          {:function, _, _, _, instructions} ->
            IO.puts("    Total instructions: #{length(instructions)}")
            analyze_instructions(instructions)

          _ ->
            IO.puts("    Function not found")
        end

      _ ->
        IO.puts("  Could not load bytecode")
    end
  end

  defp analyze_instructions(instructions) do
    # Count instruction types
    counts = Enum.frequencies(Enum.map(instructions, fn
      {op, _} -> op
      {op, _, _} -> op
      {op, _, _, _} -> op
      {op, _, _, _, _} -> op
      {op, _, _, _, _, _} -> op
      op when is_atom(op) -> op
      _ -> :other
    end))

    # Key instructions for performance
    key_ops = [:bs_create_bin, :bs_match, :get_map_elements, :call, :gc_bif]

    IO.puts("    Key instruction counts:")
    for op <- key_ops do
      count = Map.get(counts, op, 0)
      if count > 0 do
        IO.puts("      #{op}: #{count}")
      end
    end

    # JIT-friendly patterns
    binary_ops = Map.get(counts, :bs_create_bin, 0) + Map.get(counts, :bs_match, 0)
    if binary_ops > 0 do
      IO.puts("    ✓ Binary operations detected (#{binary_ops}) - JIT-friendly")
    end
  end
end

# Run if executed directly
if System.argv() != [] or true do
  Bench.JITAnalysis.run()
end
