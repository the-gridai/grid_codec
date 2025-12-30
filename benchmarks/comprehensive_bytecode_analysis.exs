# Comprehensive Bytecode and Performance Analysis
#
# This script:
# 1. Compiles codecs to actual .beam files so we can disassemble them
# 2. Tests ALL GridCodec types
# 3. Tests large objects (many fields, large groups)
# 4. Provides detailed timing breakdown

defmodule Analysis do
  @output_dir "artifacts/bytecode_analysis"

  def run do
    File.mkdir_p!(@output_dir)

    IO.puts("=" |> String.duplicate(70))
    IO.puts("COMPREHENSIVE GRIDCODEC BYTECODE & PERFORMANCE ANALYSIS")
    IO.puts("=" |> String.duplicate(70))

    # Part 1: Analyze all primitive types
    analyze_all_types()

    # Part 2: Analyze large objects
    analyze_large_objects()

    # Part 3: Disassemble actual compiled modules
    disassemble_modules()

    # Part 4: Identify hotspots per operation
    identify_hotspots()

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("Analysis complete. Results saved to #{@output_dir}/")
    IO.puts(String.duplicate("=", 70))
  end

  # ==========================================================================
  # PART 1: Analyze ALL primitive types
  # ==========================================================================

  def analyze_all_types do
    IO.puts("\n" <> String.duplicate("-", 70))
    IO.puts("PART 1: ALL PRIMITIVE TYPES ENCODE/DECODE ANALYSIS")
    IO.puts(String.duplicate("-", 70))

    types = [
      {:u8, 0, 255, 1},
      {:u16, 0, 65535, 2},
      {:u32, 0, 4_294_967_295, 4},
      {:u64, 0, 18_446_744_073_709_551_615, 8},
      {:i8, -128, 127, 1},
      {:i16, -32768, 32767, 2},
      {:i32, -2_147_483_648, 2_147_483_647, 4},
      {:i64, -9_223_372_036_854_775_808, 9_223_372_036_854_775_807, 8},
      {:bool, false, true, 1},
      {:uuid, :crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(16), 16},
      {:timestamp_us, 0, System.system_time(:microsecond), 8},
      {:timestamp_ns, 0, System.system_time(:nanosecond), 8}
    ]

    IO.puts("\n  Type           | Size | Encode µs | Decode µs | Getter µs | Notes")
    IO.puts("  " <> String.duplicate("-", 65))

    results = for {type, _min, sample_val, size} <- types do
      {enc_us, dec_us, get_us} = benchmark_type(type, sample_val)

      type_str = type |> to_string() |> String.pad_trailing(14)
      size_str = size |> to_string() |> String.pad_leading(4)
      enc_str = Float.round(enc_us, 2) |> to_string() |> String.pad_leading(9)
      dec_str = Float.round(dec_us, 2) |> to_string() |> String.pad_leading(9)
      get_str = Float.round(get_us, 2) |> to_string() |> String.pad_leading(9)

      IO.puts("  #{type_str} | #{size_str} | #{enc_str} | #{dec_str} | #{get_str} |")
      {type, enc_us, dec_us, get_us}
    end

    # Variable-length types
    IO.puts("\n  Variable-length types:")
    IO.puts("  " <> String.duplicate("-", 65))

    var_types = [
      {:string8, "short", 1},
      {:string8, String.duplicate("x", 200), 1},
      {:string16, "medium string here", 2},
      {:string16, String.duplicate("y", 10_000), 2},
      {:string32, String.duplicate("z", 100_000), 4}
    ]

    for {type, sample, prefix_size} <- var_types do
      {enc_us, dec_us, _} = benchmark_var_type(type, sample)

      type_str = type |> to_string() |> String.pad_trailing(10)
      len_str = byte_size(sample) |> to_string() |> String.pad_leading(7)
      enc_str = Float.round(enc_us, 2) |> to_string() |> String.pad_leading(9)
      dec_str = Float.round(dec_us, 2) |> to_string() |> String.pad_leading(9)

      IO.puts("  #{type_str} | len=#{len_str} | #{enc_str} | #{dec_str} | prefix=#{prefix_size}")
    end

    results
  end

  defp benchmark_type(type, sample_val) do
    # Create a codec module dynamically
    codec_mod = Module.concat([Analysis, :"TypeCodec_#{type}"])

    # Define the codec
    unless function_exported?(codec_mod, :encode, 1) do
      Code.compile_quoted(
        quote do
          defmodule unquote(codec_mod) do
            use GridCodec

            defcodec do
              field(:value, unquote(type))
            end
          end
        end
      )
    end

    data = %{value: sample_val}
    iterations = 100_000

    # Benchmark encode
    {enc_time, binary} = :timer.tc(fn ->
      run_n_times(iterations, fn -> codec_mod.encode(data) end)
    end)
    binary = codec_mod.encode(data)

    # Benchmark decode
    {dec_time, _} = :timer.tc(fn ->
      run_n_times(iterations, fn -> codec_mod.decode(binary) end)
    end)

    # Benchmark getter
    envelope = codec_mod.wrap(binary)
    {get_time, _} = :timer.tc(fn ->
      run_n_times(iterations, fn -> codec_mod.get(envelope, :value) end)
    end)

    {enc_time / iterations, dec_time / iterations, get_time / iterations}
  end

  defp benchmark_var_type(type, sample_val) do
    codec_mod = Module.concat([Analysis, :"VarCodec_#{type}_#{byte_size(sample_val)}"])

    unless function_exported?(codec_mod, :encode, 1) do
      Code.compile_quoted(
        quote do
          defmodule unquote(codec_mod) do
            use GridCodec

            defcodec do
              field(:value, unquote(type))
            end
          end
        end
      )
    end

    data = %{value: sample_val}
    iterations = 10_000

    {enc_time, binary} = :timer.tc(fn ->
      run_n_times(iterations, fn -> codec_mod.encode(data) end)
    end)
    binary = codec_mod.encode(data)

    {dec_time, _} = :timer.tc(fn ->
      run_n_times(iterations, fn -> codec_mod.decode(binary) end)
    end)

    {enc_time / iterations, dec_time / iterations, 0}
  end

  defp run_n_times(0, _fun), do: :ok
  defp run_n_times(n, fun) when n >= 10 do
    fun.(); fun.(); fun.(); fun.(); fun.()
    fun.(); fun.(); fun.(); fun.(); fun.()
    run_n_times(n - 10, fun)
  end
  defp run_n_times(n, fun) do
    fun.()
    run_n_times(n - 1, fun)
  end

  # ==========================================================================
  # PART 2: Large Objects Analysis
  # ==========================================================================

  def analyze_large_objects do
    IO.puts("\n" <> String.duplicate("-", 70))
    IO.puts("PART 2: LARGE OBJECTS ANALYSIS")
    IO.puts(String.duplicate("-", 70))

    # Test codecs with many fields
    IO.puts("\n  A. Codecs with many fixed fields:")
    analyze_many_fields()

    # Test groups with many entries
    IO.puts("\n  B. Groups with many entries:")
    analyze_large_groups()

    # Test deeply nested payloads
    IO.puts("\n  C. Large string payloads:")
    analyze_large_strings()
  end

  defp analyze_many_fields do
    field_counts = [5, 10, 20, 50, 100]

    IO.puts("  Fields | Binary Size | Encode µs | Decode µs | µs/field enc | µs/field dec")
    IO.puts("  " <> String.duplicate("-", 70))

    for count <- field_counts do
      {enc_us, dec_us, bin_size} = benchmark_many_fields(count)

      count_str = count |> to_string() |> String.pad_leading(6)
      size_str = bin_size |> to_string() |> String.pad_leading(11)
      enc_str = Float.round(enc_us, 2) |> to_string() |> String.pad_leading(9)
      dec_str = Float.round(dec_us, 2) |> to_string() |> String.pad_leading(9)
      enc_per = Float.round(enc_us / count, 3) |> to_string() |> String.pad_leading(12)
      dec_per = Float.round(dec_us / count, 3) |> to_string() |> String.pad_leading(12)

      IO.puts("  #{count_str} | #{size_str} | #{enc_str} | #{dec_str} | #{enc_per} | #{dec_per}")
    end
  end

  defp benchmark_many_fields(count) do
    # Build field definitions dynamically
    field_defs = for i <- 1..count do
      name = :"field_#{i}"
      quote do: field(unquote(name), :u32)
    end

    codec_mod = Module.concat([Analysis, :"ManyFieldsCodec_#{count}"])

    unless function_exported?(codec_mod, :encode, 1) do
      Code.compile_quoted(
        quote do
          defmodule unquote(codec_mod) do
            use GridCodec

            defcodec do
              (unquote_splicing(field_defs))
            end
          end
        end
      )
    end

    # Build test data
    data = for i <- 1..count, into: %{} do
      {:"field_#{i}", i * 100}
    end

    iterations = 10_000

    {enc_time, binary} = :timer.tc(fn ->
      run_n_times(iterations, fn -> codec_mod.encode(data) end)
    end)
    binary = codec_mod.encode(data)

    {dec_time, _} = :timer.tc(fn ->
      run_n_times(iterations, fn -> codec_mod.decode(binary) end)
    end)

    {enc_time / iterations, dec_time / iterations, byte_size(binary)}
  end

  defp analyze_large_groups do
    entry_counts = [10, 100, 1000, 10_000]

    IO.puts("  Entries | Binary Size | Encode µs | Decode µs | Stream µs | µs/entry enc")
    IO.puts("  " <> String.duplicate("-", 75))

    for count <- entry_counts do
      {enc_us, dec_us, stream_us, bin_size} = benchmark_large_group(count)

      count_str = count |> to_string() |> String.pad_leading(7)
      size_str = bin_size |> to_string() |> String.pad_leading(11)
      enc_str = Float.round(enc_us, 1) |> to_string() |> String.pad_leading(9)
      dec_str = Float.round(dec_us, 1) |> to_string() |> String.pad_leading(9)
      stream_str = Float.round(stream_us, 1) |> to_string() |> String.pad_leading(9)
      enc_per = Float.round(enc_us / count, 4) |> to_string() |> String.pad_leading(12)

      IO.puts("  #{count_str} | #{size_str} | #{enc_str} | #{dec_str} | #{stream_str} | #{enc_per}")
    end
  end

  defp benchmark_large_group(entry_count) do
    defmodule Analysis.GroupHelper do
      def encode_entry(%{id: id, value: v}), do: <<id::little-64, v::little-32>>
      def decode_entry(<<id::little-64, v::little-32>>), do: {:ok, %{id: id, value: v}}
    end

    codec_mod = Module.concat([Analysis, :"LargeGroupCodec_#{entry_count}"])

    unless function_exported?(codec_mod, :encode, 1) do
      Code.compile_quoted(
        quote do
          defmodule unquote(codec_mod) do
            use GridCodec

            defcodec do
              field(:batch_id, :u64)

              group :items,
                entry_encoder: &Analysis.GroupHelper.encode_entry/1,
                entry_decoder: &Analysis.GroupHelper.decode_entry/1 do
                field(:id, :u64)
                field(:value, :u32)
              end
            end
          end
        end
      )
    end

    entries = for i <- 1..entry_count, do: %{id: i, value: i * 10}
    data = %{batch_id: 12345, items: entries}

    iterations = max(1, div(10_000, entry_count))

    {enc_time, binary} = :timer.tc(fn ->
      run_n_times(iterations, fn -> codec_mod.encode(data) end)
    end)
    binary = codec_mod.encode(data)

    {dec_time, _} = :timer.tc(fn ->
      run_n_times(iterations, fn -> codec_mod.decode(binary) end)
    end)

    # Stream iteration
    {:ok, decoded} = codec_mod.decode(binary)
    {stream_time, _} = :timer.tc(fn ->
      run_n_times(iterations, fn ->
        decoded.items |> GridCodec.Group.stream() |> Enum.to_list()
      end)
    end)

    {enc_time / iterations, dec_time / iterations, stream_time / iterations, byte_size(binary)}
  end

  defp analyze_large_strings do
    string_sizes = [100, 1_000, 10_000, 100_000, 1_000_000]

    IO.puts("  String Len | Binary Size | Encode µs | Decode µs | Bytes/µs enc | Bytes/µs dec")
    IO.puts("  " <> String.duplicate("-", 75))

    for size <- string_sizes do
      {enc_us, dec_us, bin_size} = benchmark_large_string(size)

      size_str = size |> to_string() |> String.pad_leading(10)
      bin_str = bin_size |> to_string() |> String.pad_leading(11)
      enc_str = Float.round(enc_us, 1) |> to_string() |> String.pad_leading(9)
      dec_str = Float.round(dec_us, 1) |> to_string() |> String.pad_leading(9)
      enc_rate = Float.round(size / enc_us, 0) |> trunc() |> to_string() |> String.pad_leading(12)
      dec_rate = Float.round(size / dec_us, 0) |> trunc() |> to_string() |> String.pad_leading(12)

      IO.puts("  #{size_str} | #{bin_str} | #{enc_str} | #{dec_str} | #{enc_rate} | #{dec_rate}")
    end
  end

  defp benchmark_large_string(size) do
    codec_mod = Module.concat([Analysis, :"LargeStringCodec_#{size}"])

    unless function_exported?(codec_mod, :encode, 1) do
      Code.compile_quoted(
        quote do
          defmodule unquote(codec_mod) do
            use GridCodec

            defcodec do
              field(:data, :string32)
            end
          end
        end
      )
    end

    data = %{data: String.duplicate("x", size)}
    iterations = max(1, div(10_000, max(1, div(size, 1000))))

    {enc_time, binary} = :timer.tc(fn ->
      run_n_times(iterations, fn -> codec_mod.encode(data) end)
    end)
    binary = codec_mod.encode(data)

    {dec_time, _} = :timer.tc(fn ->
      run_n_times(iterations, fn -> codec_mod.decode(binary) end)
    end)

    {enc_time / iterations, dec_time / iterations, byte_size(binary)}
  end

  # ==========================================================================
  # PART 3: BEAM Bytecode Disassembly
  # ==========================================================================

  def disassemble_modules do
    IO.puts("\n" <> String.duplicate("-", 70))
    IO.puts("PART 3: BEAM BYTECODE DISASSEMBLY")
    IO.puts(String.duplicate("-", 70))

    # Compile a simple codec to a .beam file we can analyze
    IO.puts("\n  Compiling test codec to .beam file for analysis...")

    # Write source file
    source = """
    defmodule GridCodec.BytecodeTest.SimpleCodec do
      use GridCodec

      defcodec do
        field(:id, :u64)
        field(:count, :u32)
        field(:flag, :bool)
      end
    end
    """

    source_path = Path.join(@output_dir, "simple_codec.ex")
    File.write!(source_path, source)

    # Compile to beam
    [{mod, beam_binary}] = Code.compile_string(source)
    beam_path = Path.join(@output_dir, "Elixir.GridCodec.BytecodeTest.SimpleCodec.beam")
    File.write!(beam_path, beam_binary)

    IO.puts("  Written to: #{beam_path}")
    IO.puts("  Binary size: #{byte_size(beam_binary)} bytes")

    # Disassemble
    IO.puts("\n  Disassembling encode/1...")
    disassemble_and_report(beam_path, :encode, 1)

    IO.puts("\n  Disassembling decode/1...")
    disassemble_and_report(beam_path, :decode, 1)

    IO.puts("\n  Disassembling get/2...")
    disassemble_and_report(beam_path, :get, 2)
  end

  defp disassemble_and_report(beam_path, function, arity) do
    case :beam_disasm.file(String.to_charlist(beam_path)) do
      {:beam_file, _mod, _exports, _attrs, _compile_info, code} ->
        fn_code = Enum.find(code, fn
          {:function, ^function, ^arity, _, _} -> true
          _ -> false
        end)

        case fn_code do
          {:function, _, _, entry, instructions} ->
            IO.puts("    Entry point: #{entry}")
            IO.puts("    Total instructions: #{length(instructions)}")

            # Count instruction types
            counts = instructions
              |> Enum.map(&instruction_type/1)
              |> Enum.frequencies()

            IO.puts("    Instruction breakdown:")
            counts
            |> Enum.sort_by(fn {_, c} -> -c end)
            |> Enum.take(10)
            |> Enum.each(fn {op, count} ->
              IO.puts("      #{op}: #{count}")
            end)

            # Save full disassembly to file
            output_file = Path.join(@output_dir, "disasm_#{function}_#{arity}.txt")
            File.write!(output_file, inspect(instructions, pretty: true, limit: :infinity))
            IO.puts("    Full disassembly saved to: #{output_file}")

          nil ->
            IO.puts("    Function not found")
        end

      {:error, _, reason} ->
        IO.puts("    Disassembly error: #{inspect(reason)}")
    end
  end

  defp instruction_type(instr) do
    case instr do
      {op, _} -> op
      {op, _, _} -> op
      {op, _, _, _} -> op
      {op, _, _, _, _} -> op
      {op, _, _, _, _, _} -> op
      {op, _, _, _, _, _, _} -> op
      op when is_atom(op) -> op
      _ -> :other
    end
  end

  # ==========================================================================
  # PART 4: Identify Hotspots
  # ==========================================================================

  def identify_hotspots do
    IO.puts("\n" <> String.duplicate("-", 70))
    IO.puts("PART 4: OPERATION HOTSPOT ANALYSIS")
    IO.puts(String.duplicate("-", 70))

    IO.puts("\n  Comparing GridCodec to hand-written code for a 3-field codec:")
    IO.puts("")

    # Hand-written encode
    data = %{id: 12345, count: 100, flag: true}
    iterations = 500_000

    # GridCodec version
    codec_mod = Analysis.TypeCodec_u64
    gc_data = %{value: 12345}

    IO.puts("  Operation                    | GridCodec µs | Manual µs | Ratio")
    IO.puts("  " <> String.duplicate("-", 60))

    # Test 1: Simple value encode
    {gc_enc, _} = :timer.tc(fn ->
      run_n_times(iterations, fn -> codec_mod.encode(gc_data) end)
    end)

    {manual_enc, _} = :timer.tc(fn ->
      run_n_times(iterations, fn ->
        id = Map.get(gc_data, :value) || 0
        <<id::little-64>>
      end)
    end)

    print_comparison("Single u64 encode", gc_enc / iterations, manual_enc / iterations)

    # Test 2: Map.get overhead
    {map_get_time, _} = :timer.tc(fn ->
      run_n_times(iterations, fn ->
        Map.get(data, :id)
        Map.get(data, :count)
        Map.get(data, :flag)
      end)
    end)
    IO.puts("  Map.get (3 fields)           | #{Float.round(map_get_time / iterations, 3)} µs")

    # Test 3: Binary construction overhead
    id = 12345
    count = 100
    flag = 1
    {bin_time, _} = :timer.tc(fn ->
      run_n_times(iterations, fn ->
        <<id::little-64, count::little-32, flag::8>>
      end)
    end)
    IO.puts("  Binary <<>> (3 fields)       | #{Float.round(bin_time / iterations, 3)} µs")

    # Test 4: Case statement overhead
    {case_time, _} = :timer.tc(fn ->
      run_n_times(iterations, fn ->
        case Map.get(data, :id, 0) do nil -> 0; v -> v end
        case Map.get(data, :count, 0) do nil -> 0; v -> v end
        case Map.get(data, :flag, 255) do true -> 1; false -> 0; _ -> 255 end
      end)
    end)
    IO.puts("  case + Map.get (3 fields)    | #{Float.round(case_time / iterations, 3)} µs")

    # Test 5: case inside binary vs outside
    IO.puts("\n  Critical insight - case placement in binary:")

    {inside_time, _} = :timer.tc(fn ->
      run_n_times(iterations, fn ->
        <<
          case Map.get(data, :id, 0) do nil -> 0; v -> v end :: little-64,
          case Map.get(data, :count, 0) do nil -> 0; v -> v end :: little-32,
          case Map.get(data, :flag, 255) do true -> 1; false -> 0; _ -> 255 end :: 8
        >>
      end)
    end)

    {outside_time, _} = :timer.tc(fn ->
      run_n_times(iterations, fn ->
        id = case Map.get(data, :id, 0) do nil -> 0; v -> v end
        count = case Map.get(data, :count, 0) do nil -> 0; v -> v end
        flag = case Map.get(data, :flag, 255) do true -> 1; false -> 0; _ -> 255 end
        <<id::little-64, count::little-32, flag::8>>
      end)
    end)

    IO.puts("  case INSIDE <<>>             | #{Float.round(inside_time / iterations, 3)} µs (current GridCodec)")
    IO.puts("  case OUTSIDE <<>> (extract)  | #{Float.round(outside_time / iterations, 3)} µs (potential optimization)")
    IO.puts("  Improvement opportunity      | #{Float.round((inside_time - outside_time) / inside_time * 100, 1)}% faster")

    # Summary
    IO.puts("\n  Summary:")
    IO.puts("  - Map.get is fast (~#{Float.round(map_get_time / iterations / 3, 3)} µs per field)")
    IO.puts("  - Binary construction is very fast (~#{Float.round(bin_time / iterations, 3)} µs)")
    IO.puts("  - case statements add overhead (~#{Float.round((case_time - map_get_time) / iterations, 3)} µs for nil handling)")
    IO.puts("  - case INSIDE <<>> is #{Float.round(inside_time / outside_time, 1)}x slower than case OUTSIDE")
  end

  defp print_comparison(label, gc_us, manual_us) do
    label_str = String.pad_trailing(label, 28)
    gc_str = Float.round(gc_us, 3) |> to_string() |> String.pad_leading(12)
    manual_str = Float.round(manual_us, 3) |> to_string() |> String.pad_leading(9)
    ratio = Float.round(gc_us / manual_us, 2)
    ratio_str = "#{ratio}x" |> String.pad_leading(7)
    IO.puts("  #{label_str} | #{gc_str} | #{manual_str} | #{ratio_str}")
  end
end

Analysis.run()
