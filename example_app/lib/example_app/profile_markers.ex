defmodule ExampleApp.ProfileMarkers do
  @moduledoc """
  Profile markers for identifying operations in perf profiles.

  These are specially-named functions that show up distinctly in perf output,
  making it easy to identify specific code sections in flame graphs and reports.

  ## How It Works

  Each marker is a thin wrapper function with a distinctive name pattern:
  `__profile_<name>__/1`. When profiling, these names appear in:
  - Flame graphs (as distinct bars)
  - perf reports (searchable by name)
  - Call stacks (showing execution context)

  ## Usage

      # Tag an encode operation
      ProfileMarkers.mark(:encode_order) do
        OrderCreated.encode(order)
      end

      # Tag a decode operation
      ProfileMarkers.mark(:decode_order) do
        OrderCreated.decode(binary)
      end

      # Multiple markers for granular analysis
      ProfileMarkers.mark(:full_roundtrip) do
        binary = ProfileMarkers.mark(:encode_phase) do
          OrderCreated.encode(order)
        end

        ProfileMarkers.mark(:decode_phase) do
          OrderCreated.decode(binary)
        end
      end

  ## Viewing in Profiles

  After profiling, search for markers:

      # In flame graph (browser): Ctrl+F "profile_encode"
      # In perf report:
      grep "__profile_" profile/output/report_flat.txt

  ## Performance Impact

  Markers add ~1-2 function calls of overhead. For profiling purposes,
  this is negligible compared to the operations being measured.
  """

  @doc """
  Wrap a block of code with a named profile marker.

  The marker name will appear in perf profiles, allowing you to identify
  specific operations in flame graphs and reports.

  ## Examples

      ProfileMarkers.mark(:my_operation) do
        expensive_computation()
      end

  """
  defmacro mark(name, do: block) do
    marker_name = :"__profile_#{name}__"

    quote do
      unquote(__MODULE__).unquote(marker_name)(fn -> unquote(block) end)
    end
  end

  # Generate marker functions for common operations
  # Each creates a distinctly-named function that shows up in perf

  @markers [
    # Encoding markers
    :encode,
    :encode_order,
    :encode_trade,
    :encode_header,
    :encode_payload,
    :encode_field,
    :encode_string,
    :encode_timestamp,

    # Decoding markers
    :decode,
    :decode_order,
    :decode_trade,
    :decode_header,
    :decode_payload,
    :decode_field,
    :decode_string,
    :decode_timestamp,

    # Roundtrip markers
    :roundtrip,
    :full_roundtrip,

    # Phase markers
    :warmup_phase,
    :profile_phase,
    :encode_phase,
    :decode_phase,

    # Custom markers (add more as needed)
    :custom_1,
    :custom_2,
    :custom_3,
    :batch_operation,
    :single_operation
  ]

  for marker <- @markers do
    func_name = :"__profile_#{marker}__"

    @doc false
    def unquote(func_name)(fun) when is_function(fun, 0) do
      fun.()
    end
  end

  @doc """
  List all available profile markers.
  """
  def available_markers, do: @markers

  @doc """
  Create a custom marker at runtime (less efficient, but flexible).

  For best performance, use the compile-time `mark/2` macro instead.
  """
  def dynamic_mark(name, fun) when is_function(fun, 0) do
    # This shows up as "dynamic_mark" in profiles but includes the name in the call
    apply(__MODULE__, :__profile_custom_dynamic__, [name, fun])
  end

  @doc false
  def __profile_custom_dynamic__(_name, fun), do: fun.()
end
