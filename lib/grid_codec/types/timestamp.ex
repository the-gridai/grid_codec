defmodule GridCodec.Types.TimestampMicros do
  @moduledoc """
  Microsecond timestamp type (i64).

  Encodes timestamps as microseconds since Unix epoch.
  Compatible with Elixir's `DateTime` which uses microsecond precision.

  ## Wire Format

      ┌─────────────────────────────────────────┐
      │  microseconds (i64 LE)                  │
      └─────────────────────────────────────────┘
      Total: 8 bytes

  ## Range

  - Min: -292,277 years before epoch
  - Max: +292,277 years after epoch

  ## Null Representation

  Uses `0` as the null sentinel (Unix epoch is rarely used as actual data).

  ## Usage

      defcodec do
        field :created_at, :timestamp_us
        field :updated_at, :timestamp_us
      end

      # Encode with DateTime
      data = %{created_at: DateTime.utc_now(), updated_at: nil}

      # Or encode with integer microseconds
      data = %{created_at: System.system_time(:microsecond)}
  """

  @behaviour GridCodec.Type

  @size 8
  @alignment 8
  @null_value 0

  @impl true
  def size, do: @size

  @impl true
  def alignment, do: @alignment

  @impl true
  def null_value, do: @null_value

  @impl true
  def encode_ast(field_name, default, _endian, data_var) do
    quote do
      GridCodec.Types.TimestampMicros.encode_value(
        Map.get(unquote(data_var), unquote(field_name), unquote(default))
      ) :: binary
    end
  end

  @doc false
  def encode_value(nil), do: <<@null_value::little-signed-64>>
  def encode_value(%DateTime{} = dt), do: <<DateTime.to_unix(dt, :microsecond)::little-signed-64>>
  def encode_value(n) when is_integer(n), do: <<n::little-signed-64>>

  @impl true
  def decode_pattern_ast(var, _endian) do
    quote do: unquote(var) :: little - signed - 64
  end

  @impl true
  def decode_value_ast(var) do
    quote do
      case unquote(var) do
        0 -> nil
        us -> us
      end
    end
  end

  @impl true
  def getter_ast(offset, _endian, payload_var) do
    quote do
      <<_::binary-size(unquote(offset)), us::little-signed-64, _::binary>> =
        unquote(payload_var)

      case us do
        0 -> nil
        _ -> us
      end
    end
  end

  if Code.ensure_loaded?(GridCodec.Generators) do
    @impl true
    def generator do
      import StreamData

      one_of([
        # Recent timestamps (2020-2030)
        integer(1_577_836_800_000_000..1_893_456_000_000_000),
        # Negative timestamps (before epoch)
        integer(-1_000_000_000_000..-1),
        # Nil
        constant(nil)
      ])
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Converts microseconds to DateTime.
  """
  @spec to_datetime(integer() | nil) :: DateTime.t() | nil
  def to_datetime(nil), do: nil
  def to_datetime(0), do: nil
  def to_datetime(us) when is_integer(us), do: DateTime.from_unix!(us, :microsecond)

  @doc """
  Converts DateTime to microseconds.
  """
  @spec from_datetime(DateTime.t() | nil) :: integer()
  def from_datetime(nil), do: 0
  def from_datetime(%DateTime{} = dt), do: DateTime.to_unix(dt, :microsecond)
end

# ============================================================================
# Nanosecond Timestamp
# ============================================================================

defmodule GridCodec.Types.TimestampNanos do
  @moduledoc """
  Nanosecond timestamp type (i64).

  Encodes timestamps as nanoseconds since Unix epoch.
  Compatible with `System.system_time(:nanosecond)`.

  ## Wire Format

      ┌─────────────────────────────────────────┐
      │  nanoseconds (i64 LE)                   │
      └─────────────────────────────────────────┘
      Total: 8 bytes

  ## Range

  - Min: -292 years before epoch
  - Max: +292 years after epoch

  ## Null Representation

  Uses `0` as the null sentinel.

  ## Usage

      defcodec do
        field :event_time, :timestamp_ns
      end

      # Encode with System.system_time
      data = %{event_time: System.system_time(:nanosecond)}

      # Or DateTime (converted to nanos)
      data = %{event_time: DateTime.utc_now()}
  """

  @behaviour GridCodec.Type

  @size 8
  @alignment 8
  @null_value 0

  @impl true
  def size, do: @size

  @impl true
  def alignment, do: @alignment

  @impl true
  def null_value, do: @null_value

  @impl true
  def encode_ast(field_name, default, _endian, data_var) do
    quote do
      GridCodec.Types.TimestampNanos.encode_value(
        Map.get(unquote(data_var), unquote(field_name), unquote(default))
      ) :: binary
    end
  end

  @doc false
  def encode_value(nil), do: <<@null_value::little-signed-64>>
  def encode_value(%DateTime{} = dt), do: <<DateTime.to_unix(dt, :nanosecond)::little-signed-64>>
  def encode_value(n) when is_integer(n), do: <<n::little-signed-64>>

  @impl true
  def decode_pattern_ast(var, _endian) do
    quote do: unquote(var) :: little - signed - 64
  end

  @impl true
  def decode_value_ast(var) do
    quote do
      case unquote(var) do
        0 -> nil
        ns -> ns
      end
    end
  end

  @impl true
  def getter_ast(offset, _endian, payload_var) do
    quote do
      <<_::binary-size(unquote(offset)), ns::little-signed-64, _::binary>> =
        unquote(payload_var)

      case ns do
        0 -> nil
        _ -> ns
      end
    end
  end

  if Code.ensure_loaded?(GridCodec.Generators) do
    @impl true
    def generator do
      import StreamData

      one_of([
        # Recent timestamps (2020-2030 in nanos)
        integer(1_577_836_800_000_000_000..1_893_456_000_000_000_000),
        # Small negative
        integer(-1_000_000_000_000_000..-1),
        # Nil
        constant(nil)
      ])
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Converts nanoseconds to DateTime.

  Note: DateTime only supports microsecond precision, so nanoseconds are truncated.
  """
  @spec to_datetime(integer() | nil) :: DateTime.t() | nil
  def to_datetime(nil), do: nil
  def to_datetime(0), do: nil
  def to_datetime(ns) when is_integer(ns), do: DateTime.from_unix!(ns, :nanosecond)

  @doc """
  Converts DateTime to nanoseconds.
  """
  @spec from_datetime(DateTime.t() | nil) :: integer()
  def from_datetime(nil), do: 0
  def from_datetime(%DateTime{} = dt), do: DateTime.to_unix(dt, :nanosecond)
end
