# Microstate Accounting Profiler
#
# Uses :msacc to see what the BEAM schedulers are doing at a hardware level.
# This reveals time spent in emulator, GC, binary heap management, etc.

IO.puts(String.duplicate("=", 80))
IO.puts("MICROSTATE ACCOUNTING PROFILER")
IO.puts(String.duplicate("=", 80))

# Define test codec
defmodule MsaccCodec do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:count, :u32)
    field(:flag, :bool)
  end
end

defmodule MsaccStringCodec do
  use GridCodec

  defcodec do
    field(:id, :u64)
    field(:name, :string16)
    field(:description, :string16)
  end
end

IO.puts("""

MICROSTATE CATEGORIES:
----------------------
- emulator      : Executing Erlang/Elixir code (WANT THIS HIGH)
- aux           : Auxiliary work (timers, etc.)
- check_io      : Checking for I/O events
- gc            : Garbage collection (WANT THIS LOW)
- gc_full       : Full GC sweeps (WANT THIS VERY LOW)
- sleep         : Scheduler sleeping (idle)
- port          : Port operations
- send          : Sending messages
- receive       : Receiving messages
- timers        : Timer management
- bif           : Built-in function execution
- busy_wait     : Active waiting
- alloc         : Memory allocation
- nif           : NIF execution
- bin_vheap     : Binary virtual heap (WATCH FOR ZERO-COPY ISSUES)

""")

# Test data
simple_data = %{id: 12345678901234, count: 1000000, flag: true}

string_data = %{
  id: 12345,
  name: "Test Name",
  description: "A longer description that might trigger different binary behavior"
}

simple_bin = MsaccCodec.encode(simple_data)
string_bin = MsaccStringCodec.encode(string_data)

# Helper to run msacc analysis
run_msacc_test = fn name, duration_ms, workload_fn ->
  IO.puts("\n" <> String.duplicate("-", 80))
  IO.puts("TEST: #{name}")
  IO.puts(String.duplicate("-", 80))

  # Start microstate accounting
  :msacc.start(duration_ms)

  # Run workload
  workload_fn.()

  # Stop and get stats
  stats = :msacc.stop()

  # Print results
  :msacc.print(stats)

  stats
end

# Test 1: Pure Encode (Fixed Fields)
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("TEST 1: ENCODE FIXED FIELDS (100k iterations)")
IO.puts(String.duplicate("=", 80))

run_msacc_test.("Encode Fixed", 2000, fn ->
  for _ <- 1..100_000 do
    MsaccCodec.encode(simple_data)
  end
end)

# Test 2: Pure Decode (Fixed Fields)
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("TEST 2: DECODE FIXED FIELDS (100k iterations)")
IO.puts(String.duplicate("=", 80))

run_msacc_test.("Decode Fixed", 2000, fn ->
  for _ <- 1..100_000 do
    MsaccCodec.decode(simple_bin)
  end
end)

# Test 3: Zero-Copy Access
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("TEST 3: ZERO-COPY ACCESS (100k iterations)")
IO.puts(String.duplicate("=", 80))

run_msacc_test.("Zero-Copy Get", 2000, fn ->
  for _ <- 1..100_000 do
    MsaccCodec.get(simple_bin, :id)
    MsaccCodec.get(simple_bin, :count)
    MsaccCodec.get(simple_bin, :flag)
  end
end)

# Test 4: String Encode (Variable Length)
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("TEST 4: ENCODE VAR FIELDS (50k iterations)")
IO.puts(String.duplicate("=", 80))

run_msacc_test.("Encode Var", 2000, fn ->
  for _ <- 1..50_000 do
    MsaccStringCodec.encode(string_data)
  end
end)

# Test 5: String Decode
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("TEST 5: DECODE VAR FIELDS (50k iterations)")
IO.puts(String.duplicate("=", 80))

run_msacc_test.("Decode Var", 2000, fn ->
  for _ <- 1..50_000 do
    MsaccStringCodec.decode(string_bin)
  end
end)

# Test 6: Large Binary (to test zero-copy behavior)
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("TEST 6: LARGE BINARY HANDLING")
IO.puts(String.duplicate("=", 80))

large_string = String.duplicate("x", 10_000)

large_data = %{
  id: 12345,
  name: "short",
  description: large_string
}

run_msacc_test.("Large Binary", 2000, fn ->
  for _ <- 1..10_000 do
    bin = MsaccStringCodec.encode(large_data)
    MsaccStringCodec.decode(bin)
  end
end)

# Summary
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("INTERPRETATION GUIDE")
IO.puts(String.duplicate("=", 80))

IO.puts("""

HEALTHY PROFILE FOR SBE-STYLE ENCODING:
---------------------------------------
✓ emulator > 90%    : Most time in actual code execution
✓ gc < 5%           : Minimal garbage collection
✓ gc_full < 1%      : No major GC pauses
✓ bin_vheap < 2%    : Binary heap well-managed
✓ sleep high        : Good for I/O bound (bad for CPU bound)

RED FLAGS:
----------
✗ gc > 10%          : Too much allocation, review data structures
✗ gc_full > 5%      : Large heap, possible memory leak
✗ bin_vheap > 10%   : Binary reference counting overhead
✗ alloc > 5%        : Memory allocator contention

FOR GRIDCODEC SPECIFICALLY:
---------------------------
- Fixed field encode should be nearly 100% emulator
- Variable field encode may show more alloc (binary building)
- Zero-copy access should show no gc or bin_vheap

If bin_vheap is high:
  → Check if binaries > 64 bytes are being shared across processes
  → Consider process-local binary building strategies

""")
