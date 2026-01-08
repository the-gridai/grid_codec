defmodule GridCodec.Envelope do
  @moduledoc """
  Zero-copy wrapper for accessing GridCodec binary messages.

  The Envelope provides lazy, zero-copy field access without requiring
  full decode of the message. This is critical for high-performance
  scenarios like event sourcing where messages may be routed based on
  a single field.

  ## BEAM Binary Sharing

  Elixir/Erlang binaries larger than 64 bytes are reference-counted
  and can be shared across processes without copying. The Envelope
  leverages this by creating sub-binary references rather than
  extracting values.

  ## Usage

      # Wrap a binary
      env = GridCodec.Envelope.wrap(binary, MyCodec)

      # Access fields (O(1) for fixed-size types)
      id = GridCodec.Envelope.get(env, :id)
      price = GridCodec.Envelope.get(env, :price)

      # Decode fully when needed
      {:ok, map} = GridCodec.Envelope.decode(env)

  ## Performance Characteristics

  | Operation | Fixed Field | Variable Field | Group |
  |-----------|-------------|----------------|-------|
  | get/2     | O(1)        | Requires decode | Requires decode |
  | decode/1  | O(n)        | O(n)           | O(n)  |

  Variable-length fields and groups cannot be accessed via `get/2` without
  a full decode, as their positions depend on preceding variable-length data.

  ## Fan-out Optimization

  For PubSub/broadcast scenarios, wrap once and share the envelope:

      # In publisher
      binary = MyEvent.encode(data)
      env = GridCodec.Envelope.wrap(binary, MyEvent)

      # Broadcast the envelope (binary reference, not copy)
      Phoenix.PubSub.broadcast(topic, {:event, env})

      # In N subscribers - no decode until needed
      def handle_info({:event, env}, state) do
        if GridCodec.Envelope.get(env, :user_id) == state.user_id do
          {:ok, event} = GridCodec.Envelope.decode(env)
          # Process event
        else
          # Skip without decoding
        end
      end

  ## Struct

  The envelope contains:
  - `binary` - The raw binary message (reference, not copy)
  - `codec` - The codec module for decoding
  - `schema` - Cached schema metadata
  """

  @type t :: %__MODULE__{
          binary: binary(),
          codec: module(),
          schema: map() | nil
        }

  defstruct [:binary, :codec, :schema]

  @doc """
  Wraps a binary in an envelope for zero-copy access.

  ## Example

      env = GridCodec.Envelope.wrap(binary, MyCodec)
  """
  @spec wrap(binary(), module()) :: t()
  def wrap(binary, codec) when is_binary(binary) and is_atom(codec) do
    schema =
      if function_exported?(codec, :__schema__, 0) do
        codec.__schema__()
      end

    %__MODULE__{
      binary: binary,
      codec: codec,
      schema: schema
    }
  end

  @doc """
  Gets a field from the wrapped binary.

  For fixed-size fields, this is O(1) using compile-time offsets.
  Variable-length fields and groups require full decode.

  Note: This uses runtime dispatch. For maximum performance in hot paths,
  use the codec's `get/2` macro directly with `require`:

      require MyCodec
      value = MyCodec.get(binary, :field)

  ## Example

      id = GridCodec.Envelope.get(env, :id)
  """
  @spec get(t(), atom()) :: term()
  def get(%__MODULE__{binary: binary, codec: codec}, field_name) do
    # Use GridCodec.get/2 with field spec for runtime dispatch
    spec = codec.__field_info__(field_name)
    GridCodec.get(binary, spec)
  end

  @doc """
  Gets multiple fields at once.

  Slightly more efficient than multiple get/2 calls.

  ## Example

      %{id: id, price: price} = GridCodec.Envelope.get_many(env, [:id, :price])
  """
  @spec get_many(t(), [atom()]) :: map()
  def get_many(%__MODULE__{} = env, field_names) when is_list(field_names) do
    Map.new(field_names, fn name -> {name, get(env, name)} end)
  end

  @doc """
  Fully decodes the wrapped binary.

  Returns the complete decoded map.

  ## Example

      {:ok, data} = GridCodec.Envelope.decode(env)
  """
  @spec decode(t()) :: {:ok, map()} | {:error, term()}
  def decode(%__MODULE__{binary: binary, codec: codec}) do
    # Envelope stores payload without header
    codec.decode(binary, header: false)
  end

  @doc """
  Fully decodes the wrapped binary, raising on error.
  """
  @spec decode!(t()) :: map()
  def decode!(%__MODULE__{} = env) do
    case decode(env) do
      {:ok, data} -> data
      {:error, reason} -> raise "Decode failed: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the raw binary from the envelope.
  """
  @spec binary(t()) :: binary()
  def binary(%__MODULE__{binary: bin}), do: bin

  @doc """
  Returns the codec module.
  """
  @spec codec(t()) :: module()
  def codec(%__MODULE__{codec: mod}), do: mod

  @doc """
  Returns the byte size of the wrapped binary.
  """
  @spec byte_size(t()) :: non_neg_integer()
  def byte_size(%__MODULE__{binary: bin}), do: Kernel.byte_size(bin)

  @doc """
  Returns schema metadata if available.
  """
  @spec schema(t()) :: map() | nil
  def schema(%__MODULE__{schema: s}), do: s
end
