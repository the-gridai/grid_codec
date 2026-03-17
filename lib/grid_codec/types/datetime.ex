defmodule GridCodec.Types.DateTimeMicros do
  @moduledoc """
  DateTime-domain microsecond timestamp type (i64).

  Same wire format as `:timestamp_us` (8-byte i64 LE), but the domain type is
  `%DateTime{}` instead of raw integer microseconds. Both `coerce_ast` and
  `decode_value_ast` produce `%DateTime{}`, so the `new/1 → encode → decode`
  identity invariant holds.

  ## Wire Format

      ┌─────────────────────────────────────────┐
      │  microseconds (i64 LE)                  │
      └─────────────────────────────────────────┘
      Total: 8 bytes

  Wire-compatible with `:timestamp_us` — binaries are interchangeable.

  ## When to Use

  | Type | Domain | Best For |
  |------|--------|----------|
  | `:timestamp_us` | `integer()` | Hot paths, high-throughput pipelines |
  | `:datetime_us` | `%DateTime{}` | Application code, JSON APIs, Ecto-like workflows |

  ## Usage

      defcodec do
        field :created_at, :datetime_us
        field :updated_at, :datetime_us
      end

      {:ok, event} = MyCodec.new(%{created_at: DateTime.utc_now()})
      event.created_at
      #=> ~U[2024-06-15 12:30:00.123456Z]

      # Also accepts integers and ISO 8601 strings
      {:ok, event} = MyCodec.new(%{created_at: 1_718_451_000_123_456})
      {:ok, event} = MyCodec.new(%{created_at: "2024-06-15T12:30:00Z"})

  ## Null Representation

  Uses `0` (Unix epoch) as the null sentinel, same as `:timestamp_us`.
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
    dt_mod = DateTime

    quote do
      case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
        nil -> 0
        %unquote(dt_mod){} = dt -> unquote(dt_mod).to_unix(dt, :microsecond)
        n when is_integer(n) -> n
      end :: little - signed - 64
    end
  end

  @doc false
  def encode_value(nil), do: <<@null_value::little-signed-64>>

  def encode_value(%DateTime{} = dt),
    do: <<DateTime.to_unix(dt, :microsecond)::little-signed-64>>

  def encode_value(n) when is_integer(n), do: <<n::little-signed-64>>

  @impl true
  def decode_pattern_ast(var, _endian) do
    quote do: unquote(var) :: little - signed - 64
  end

  @impl true
  def decode_value_ast(var) do
    dt_mod = DateTime

    quote do
      case unquote(var) do
        0 -> nil
        us -> unquote(dt_mod).from_unix!(us, :microsecond)
      end
    end
  end

  @impl true
  def getter_ast(offset, _endian, payload_var) do
    dt_mod = DateTime

    quote do
      <<_::binary-size(unquote(offset)), us::little-signed-64, _::binary>> =
        unquote(payload_var)

      case us do
        0 -> nil
        _ -> unquote(dt_mod).from_unix!(us, :microsecond)
      end
    end
  end

  @doc """
  Extracts a datetime_us from a binary at the given offset.
  """
  def get_value(binary, offset, _endian) when is_binary(binary) do
    <<_::binary-size(offset), us::little-signed-64, _::binary>> = binary

    case us do
      0 -> nil
      _ -> DateTime.from_unix!(us, :microsecond)
    end
  end

  @impl true
  def coerce_ast(var) do
    dt_mod = DateTime

    quote do
      case unquote(var) do
        nil ->
          {:ok, nil}

        %unquote(dt_mod){} = v ->
          {:ok, v}

        v when is_integer(v) ->
          {:ok, unquote(dt_mod).from_unix!(v, :microsecond)}

        v when is_binary(v) ->
          case unquote(dt_mod).from_iso8601(v) do
            {:ok, dt, _offset} -> {:ok, dt}
            _ -> {:error, "cannot parse datetime from #{inspect(v)}"}
          end

        v ->
          {:error, "expected DateTime, integer, or ISO 8601 string, got #{inspect(v)}"}
      end
    end
  end

  @impl true
  def validate_ast(var, field, mod) do
    dt_mod = DateTime

    quote do
      case unquote(var) do
        nil ->
          :ok

        %unquote(dt_mod){} ->
          :ok

        v when is_integer(v) ->
          :ok

        v ->
          raise GridCodec.ValidationError.type_mismatch(
                  unquote(mod),
                  unquote(field),
                  :datetime_us,
                  v,
                  "DateTime, integer, or nil"
                )
      end
    end
  end

  @impl true
  def compare_values(left, right) do
    case DateTime.compare(coerce_compare_value(left), coerce_compare_value(right)) do
      :lt -> :lt
      :eq -> :eq
      :gt -> :gt
    end
  end

  if Code.ensure_loaded?(StreamData) do
    @impl true
    def generator do
      import StreamData

      one_of([
        map(
          integer(1_577_836_800_000_000..1_893_456_000_000_000),
          &DateTime.from_unix!(&1, :microsecond)
        ),
        constant(nil)
      ])
    end
  end

  defp coerce_compare_value(%DateTime{} = dt), do: dt

  defp coerce_compare_value(value) when is_integer(value),
    do: DateTime.from_unix!(value, :microsecond)

  defp coerce_compare_value(other) do
    raise ArgumentError,
          "unsupported datetime_us compare value: #{inspect(other)}. " <>
            "Expected DateTime.t or integer"
  end
end

# ============================================================================
# DateTime Nanoseconds
# ============================================================================

defmodule GridCodec.Types.DateTimeNanos do
  @moduledoc """
  DateTime-domain nanosecond timestamp type (i64).

  Same wire format as `:timestamp_ns` (8-byte i64 LE), but the domain type is
  `%DateTime{}` instead of raw integer nanoseconds. Both `coerce_ast` and
  `decode_value_ast` produce `%DateTime{}`.

  ## Wire Format

      ┌─────────────────────────────────────────┐
      │  nanoseconds (i64 LE)                   │
      └─────────────────────────────────────────┘
      Total: 8 bytes

  Wire-compatible with `:timestamp_ns` — binaries are interchangeable.

  ## When to Use

  | Type | Domain | Best For |
  |------|--------|----------|
  | `:timestamp_ns` | `integer()` | Hot paths, high-throughput pipelines |
  | `:datetime_ns` | `%DateTime{}` | Application code, JSON APIs |

  Note: Elixir's `DateTime` supports microsecond precision. `DateTime` inputs
  therefore round-trip at microsecond precision. Integer nanosecond inputs are
  accepted only when they are microsecond-aligned (`rem(ns, 1000) == 0`);
  sub-microsecond values are rejected to avoid silent precision loss.

  ## Usage

      defcodec do
        field :event_time, :datetime_ns
      end

      {:ok, event} = MyCodec.new(%{event_time: DateTime.utc_now()})
      event.event_time
      #=> ~U[2024-06-15 12:30:00.123456Z]

  ## Null Representation

  Uses `0` (Unix epoch) as the null sentinel, same as `:timestamp_ns`.
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
    dt_mod = DateTime

    quote do
      case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
        nil ->
          0

        %unquote(dt_mod){} = dt ->
          unquote(dt_mod).to_unix(dt, :nanosecond)

        n when is_integer(n) and rem(n, 1000) == 0 ->
          n

        n when is_integer(n) ->
          raise ArgumentError,
                "datetime_ns integers must be microsecond-aligned, got: #{inspect(n)}"
      end :: little - signed - 64
    end
  end

  @doc false
  def encode_value(nil), do: <<@null_value::little-signed-64>>

  def encode_value(%DateTime{} = dt),
    do: <<DateTime.to_unix(dt, :nanosecond)::little-signed-64>>

  def encode_value(n) when is_integer(n) and rem(n, 1000) == 0, do: <<n::little-signed-64>>

  def encode_value(n) when is_integer(n) do
    raise ArgumentError, "datetime_ns integers must be microsecond-aligned, got: #{inspect(n)}"
  end

  @impl true
  def decode_pattern_ast(var, _endian) do
    quote do: unquote(var) :: little - signed - 64
  end

  @impl true
  def decode_value_ast(var) do
    dt_mod = DateTime

    quote do
      case unquote(var) do
        0 -> nil
        ns -> unquote(dt_mod).from_unix!(ns, :nanosecond)
      end
    end
  end

  @impl true
  def getter_ast(offset, _endian, payload_var) do
    dt_mod = DateTime

    quote do
      <<_::binary-size(unquote(offset)), ns::little-signed-64, _::binary>> =
        unquote(payload_var)

      case ns do
        0 -> nil
        _ -> unquote(dt_mod).from_unix!(ns, :nanosecond)
      end
    end
  end

  @doc """
  Extracts a datetime_ns from a binary at the given offset.
  """
  def get_value(binary, offset, _endian) when is_binary(binary) do
    <<_::binary-size(offset), ns::little-signed-64, _::binary>> = binary

    case ns do
      0 -> nil
      _ -> DateTime.from_unix!(ns, :nanosecond)
    end
  end

  @impl true
  def coerce_ast(var) do
    dt_mod = DateTime

    quote do
      case unquote(var) do
        nil ->
          {:ok, nil}

        %unquote(dt_mod){} = v ->
          {:ok, v}

        v when is_integer(v) and rem(v, 1000) == 0 ->
          {:ok, unquote(dt_mod).from_unix!(v, :nanosecond)}

        v when is_integer(v) ->
          {:error, "datetime_ns integers must be microsecond-aligned, got: #{inspect(v)}"}

        v when is_binary(v) ->
          case unquote(dt_mod).from_iso8601(v) do
            {:ok, dt, _offset} -> {:ok, dt}
            _ -> {:error, "cannot parse datetime from #{inspect(v)}"}
          end

        v ->
          {:error, "expected DateTime, integer, or ISO 8601 string, got #{inspect(v)}"}
      end
    end
  end

  @impl true
  def validate_ast(var, field, mod) do
    dt_mod = DateTime

    quote do
      case unquote(var) do
        nil ->
          :ok

        %unquote(dt_mod){} ->
          :ok

        v when is_integer(v) and rem(v, 1000) == 0 ->
          :ok

        v when is_integer(v) ->
          raise GridCodec.ValidationError.cast_error(
                  unquote(mod),
                  unquote(field),
                  :datetime_ns,
                  v,
                  "datetime_ns integers must be microsecond-aligned"
                )

        v ->
          raise GridCodec.ValidationError.type_mismatch(
                  unquote(mod),
                  unquote(field),
                  :datetime_ns,
                  v,
                  "DateTime, integer, or nil"
                )
      end
    end
  end

  @impl true
  def compare_values(left, right) do
    case DateTime.compare(coerce_compare_value(left), coerce_compare_value(right)) do
      :lt -> :lt
      :eq -> :eq
      :gt -> :gt
    end
  end

  if Code.ensure_loaded?(StreamData) do
    @impl true
    def generator do
      import StreamData

      one_of([
        map(
          integer(1_577_836_800_000_000_000..1_893_456_000_000_000_000),
          &DateTime.from_unix!(&1, :nanosecond)
        ),
        constant(nil)
      ])
    end
  end

  defp coerce_compare_value(%DateTime{} = dt), do: dt

  defp coerce_compare_value(value) when is_integer(value),
    do: DateTime.from_unix!(value, :nanosecond)

  defp coerce_compare_value(other) do
    raise ArgumentError,
          "unsupported datetime_ns compare value: #{inspect(other)}. " <>
            "Expected DateTime.t or integer"
  end
end
