defmodule ExampleApp.ProfileRunner do
  @moduledoc """
  Production-representative profiler for GridCodec.

  This module runs JIT-warmed profiling to capture accurate performance
  characteristics of the codec in a production-like environment.

  ## Usage

  Typically invoked via `./profile/run.sh`, but can also be run directly:

      # Full profile (encode + decode)
      ExampleApp.ProfileRunner.run()

      # Encode only
      ExampleApp.ProfileRunner.run(:encode)

      # Decode only
      ExampleApp.ProfileRunner.run(:decode)

  ## Separated Warmup/Profile (for noise-free profiling)

  The profiler supports running warmup and profile phases separately,
  allowing perf to only capture the actual encode/decode operations:

      # Phase 1: Run warmup (no perf)
      ExampleApp.ProfileRunner.run_warmup_only()

      # Phase 2: Run profile (with perf)
      ExampleApp.ProfileRunner.run_profile_only()

  ## Configuration

  Via application env (set by run.sh):

      Application.put_env(:gridcodec_profile, :iterations, 5_000_000)
      Application.put_env(:gridcodec_profile, :warmup, 100_000)
      Application.put_env(:gridcodec_profile, :mode, :all)
  """

  @default_warmup 100_000
  @default_iterations 5_000_000

  @doc "Run the profiler with configuration from application env."
  def run do
    mode = Application.get_env(:gridcodec_profile, :mode, :all)
    run(mode)
  end

  @doc """
  Run ONLY the warmup phase (no profiling).
  Use this before starting perf to eliminate warmup noise from profiles.
  """
  def run_warmup_only do
    mode = Application.get_env(:gridcodec_profile, :mode, :all)
    warmup = Application.get_env(:gridcodec_profile, :warmup, @default_warmup)

    # Create test data
    {order, order_bin} = create_test_data()

    # Run warmup
    warmup_jit(mode, order, order_bin, warmup)

    :ok
  end

  @doc """
  Run ONLY the profile phase (no warmup).
  Use this AFTER warmup, with perf recording, to get clean profile data.
  """
  def run_profile_only do
    mode = Application.get_env(:gridcodec_profile, :mode, :all)
    iterations = Application.get_env(:gridcodec_profile, :iterations, @default_iterations)

    print_header()

    # Create test data
    {order, order_bin} = create_test_data()
    IO.puts("Binary size: #{byte_size(order_bin)} bytes")
    IO.puts("")

    IO.puts("Profiling #{format_number(iterations)} iterations (#{mode} mode)...")
    IO.puts(">>> PROFILE START <<<")

    run_profile(mode, order, order_bin, iterations)

    IO.puts(">>> PROFILE END <<<")
    IO.puts("")
    IO.puts("Done!")
  end

  @doc """
  Run the profiler with a specific mode.

  Modes: `:all`, `:encode`, `:decode`
  """
  def run(mode) when mode in [:all, :encode, :decode] do
    warmup = Application.get_env(:gridcodec_profile, :warmup, @default_warmup)
    iterations = Application.get_env(:gridcodec_profile, :iterations, @default_iterations)

    print_header()

    # Create test data
    {order, order_bin} = create_test_data()
    IO.puts("Binary size: #{byte_size(order_bin)} bytes")
    IO.puts("")

    # Warm-up phase
    IO.puts("Phase 1: JIT warm-up (#{format_number(warmup)} iterations)...")
    warmup_jit(mode, order, order_bin, warmup)
    IO.puts("Warm-up complete.")
    IO.puts("")

    # Small pause for clean perf capture
    Process.sleep(50)

    # Profile phase
    IO.puts("Phase 2: Profiling (#{format_number(iterations)} iterations)...")
    IO.puts(">>> PROFILE START <<<")
    Process.sleep(50)

    run_profile(mode, order, order_bin, iterations)

    IO.puts(">>> PROFILE END <<<")
    IO.puts("")
    IO.puts("Done!")
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp print_header do
    version = get_gridcodec_version()
    git_info = get_git_info()

    IO.puts("")
    IO.puts("╔══════════════════════════════════════════════════════════════╗")
    IO.puts("║           GridCodec Production Profiler                      ║")
    IO.puts("╠══════════════════════════════════════════════════════════════╣")
    IO.puts("║  Version:  GridCodec #{version}")
    IO.puts("║  Git:      #{git_info}")
    IO.puts("║  Elixir:   #{System.version()}")
    IO.puts("║  OTP:      #{System.otp_release()}")
    IO.puts("╚══════════════════════════════════════════════════════════════╝")
    IO.puts("")
  end

  defp get_gridcodec_version do
    case :application.get_key(:grid_codec, :vsn) do
      {:ok, vsn} -> List.to_string(vsn)
      _ -> "dev"
    end
  end

  defp get_git_info do
    # Try to get git info from workspace
    commit =
      case System.cmd("git", ["rev-parse", "--short", "HEAD"],
             cd: "/workspace",
             stderr_to_stdout: true
           ) do
        {output, 0} -> String.trim(output)
        _ -> "unknown"
      end

    branch =
      case System.cmd("git", ["branch", "--show-current"],
             cd: "/workspace",
             stderr_to_stdout: true
           ) do
        {output, 0} -> String.trim(output)
        _ -> "unknown"
      end

    dirty =
      case System.cmd("git", ["status", "--porcelain"], cd: "/workspace", stderr_to_stdout: true) do
        {"", 0} -> ""
        {_, 0} -> "+dirty"
        _ -> ""
      end

    "#{branch}@#{commit}#{dirty}"
  end

  defp create_test_data do
    order = %ExampleApp.Events.OrderCreated{
      order_id: :crypto.strong_rand_bytes(16),
      user_id: 12_345_678_901_234_567,
      symbol: "BTCUSD",
      side: 1,
      price: 15_000_000_000,
      quantity: 100_000,
      timestamp: DateTime.utc_now(),
      flags: 7
    }

    {:ok, order_bin} = ExampleApp.Events.OrderCreated.encode(order)
    {order, order_bin}
  end

  defp warmup_jit(:all, order, order_bin, n), do: do_warmup_both(n, order, order_bin)
  defp warmup_jit(:encode, order, _order_bin, n), do: do_warmup_encode(n, order)
  defp warmup_jit(:decode, _order, order_bin, n), do: do_warmup_decode(n, order_bin)

  defp run_profile(:all, order, order_bin, n), do: do_profile_both(n, order, order_bin)
  defp run_profile(:encode, order, _order_bin, n), do: do_profile_encode(n, order)
  defp run_profile(:decode, _order, order_bin, n), do: do_profile_decode(n, order_bin)

  # Tail-recursive loops (no closure allocation overhead)
  # These use profile markers for visibility in perf output

  require ExampleApp.ProfileMarkers, as: Markers

  defp do_warmup_both(0, _order, _order_bin), do: :ok

  defp do_warmup_both(n, order, order_bin) do
    {:ok, encoded} = ExampleApp.Events.OrderCreated.encode(order)
    {:ok, _decoded} = ExampleApp.Events.OrderCreated.decode(encoded)
    do_warmup_both(n - 1, order, order_bin)
  end

  defp do_warmup_encode(0, _order), do: :ok

  defp do_warmup_encode(n, order) do
    {:ok, _} = ExampleApp.Events.OrderCreated.encode(order)
    do_warmup_encode(n - 1, order)
  end

  defp do_warmup_decode(0, _order_bin), do: :ok

  defp do_warmup_decode(n, order_bin) do
    {:ok, _decoded} = ExampleApp.Events.OrderCreated.decode(order_bin)
    do_warmup_decode(n - 1, order_bin)
  end

  # Profile functions use markers for clear identification in perf output
  # Look for "__profile_encode__" and "__profile_decode__" in flame graphs

  defp do_profile_both(0, _order, _order_bin), do: :ok

  defp do_profile_both(n, order, order_bin) do
    Markers.mark :roundtrip do
      {:ok, encoded} =
        Markers.mark :encode_order do
          ExampleApp.Events.OrderCreated.encode(order)
        end

      Markers.mark :decode_order do
        {:ok, _decoded} = ExampleApp.Events.OrderCreated.decode(encoded)
      end
    end

    do_profile_both(n - 1, order, order_bin)
  end

  defp do_profile_encode(0, _order), do: :ok

  defp do_profile_encode(n, order) do
    Markers.mark :encode_order do
      {:ok, _} = ExampleApp.Events.OrderCreated.encode(order)
    end

    do_profile_encode(n - 1, order)
  end

  defp do_profile_decode(0, _order_bin), do: :ok

  defp do_profile_decode(n, order_bin) do
    Markers.mark :decode_order do
      {:ok, _decoded} = ExampleApp.Events.OrderCreated.decode(order_bin)
    end

    do_profile_decode(n - 1, order_bin)
  end

  defp format_number(n) when n >= 1_000_000, do: "#{div(n, 1_000_000)}M"
  defp format_number(n) when n >= 1_000, do: "#{div(n, 1_000)}K"
  defp format_number(n), do: "#{n}"
end
