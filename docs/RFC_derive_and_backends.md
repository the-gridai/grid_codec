# RFC: Derive-based Codecs & Pluggable Backends

## Overview

This RFC proposes two complementary features to make GridCodec more accessible and flexible:

1. **Derive-based codec generation** - Automatic codec derivation for Elixir structs (like `@derive Jason.Encoder`)
2. **Pluggable backends** - Swappable encoding formats with a unified interface

Together, these features enable seamless adoption without major code changes.

---

## Part 1: Derive-based Codec Generation

### Motivation

Currently, using GridCodec requires defining explicit codec modules:

```elixir
# Current approach - separate codec module
defmodule MyApp.Events.UserCreated do
  use GridCodec, template_id: 1

  defcodec do
    field :user_id, :uuid
    field :name, :string
    field :age, :u8
  end
end
```

With derive, you could annotate existing structs/schemas directly:

```elixir
# Proposed: Derive on any struct
defmodule MyApp.User do
  @derive {GridCodec.Struct, 
    template_id: 1,
    fields: [
      id: :uuid,
      name: :string,
      age: :u8
    ]
  }
  
  defstruct [:id, :name, :age, :internal_field]
end

# Usage
user = %MyApp.User{id: uuid, name: "Alice", age: 30}
binary = GridCodec.Struct.encode(user)
{:ok, decoded} = GridCodec.Struct.decode(binary, MyApp.User)
```

### Design

#### 1. Protocol-based Approach

Define a protocol that structs can implement:

```elixir
defprotocol GridCodec.Encodable do
  @doc "Encodes a struct to binary using its derived codec"
  @spec encode(t()) :: binary()
  def encode(data)
  
  @doc "Encodes with header for dispatch"
  @spec encode_framed(t()) :: binary()
  def encode_framed(data)
end
```

#### 2. Derive Implementation

```elixir
defmodule GridCodec.Struct do
  @moduledoc """
  Derive-based codec generation for Elixir structs.
  
  ## Usage
  
      defmodule MyApp.User do
        @derive {GridCodec.Struct, 
          fields: [id: :uuid, name: :string, age: :u8],
          template_id: 1
        }
        defstruct [:id, :name, :age]
      end
  
  ## Options
  
  - `:fields` - Map of field names to GridCodec types (required)
  - `:template_id` - Message type identifier for dispatch (default: 0)
  - `:schema_id` - Schema namespace identifier (default: 0)
  - `:version` - Schema version (default: 1)
  - `:only` - List of fields to include (alternative to `:fields`)
  - `:except` - List of fields to exclude
  
  ## With Ecto Schemas
  
  For Ecto schemas, types can be inferred:
  
      defmodule MyApp.User do
        use Ecto.Schema
        
        @derive {GridCodec.Struct,
          template_id: 1,
          only: [:id, :name, :age]  # Types inferred from Ecto schema
        }
        
        schema "users" do
          field :name, :string
          field :age, :integer
        end
      end
  """
  
  defmacro __deriving__(module, struct, opts) do
    fields = Keyword.get(opts, :fields)
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])
    template_id = Keyword.get(opts, :template_id, 0)
    schema_id = Keyword.get(opts, :schema_id, 0)
    version = Keyword.get(opts, :version, 1)
    
    # Resolve field types
    field_specs = resolve_field_specs(module, struct, fields, only, except)
    
    quote do
      # Store codec metadata on the module
      @__gridcodec_fields__ unquote(Macro.escape(field_specs))
      @__gridcodec_template_id__ unquote(template_id)
      @__gridcodec_schema_id__ unquote(schema_id)
      @__gridcodec_version__ unquote(version)
      
      # Generate the codec at compile time
      @before_compile GridCodec.Struct.Compiler
      
      # Implement the protocol
      defimpl GridCodec.Encodable do
        def encode(struct) do
          unquote(module).__gridcodec_encode__(struct)
        end
        
        def encode_framed(struct) do
          unquote(module).__gridcodec_encode_framed__(struct)
        end
      end
    end
  end
end
```

#### 3. Ecto Integration

Automatic type inference from Ecto schemas:

```elixir
defmodule GridCodec.Struct.EctoTypeMapper do
  @moduledoc """
  Maps Ecto types to GridCodec types.
  """
  
  @type_map %{
    # Ecto type => GridCodec type
    :id => :i64,
    :binary_id => :uuid,
    :integer => :i64,
    :float => :f64,
    :decimal => :decimal,
    :boolean => :bool,
    :string => :string,
    :binary => :string,  # or :bytes when we add it
    :utc_datetime => :timestamp_us,
    :utc_datetime_usec => :timestamp_us,
    :naive_datetime => :timestamp_us,
    :date => :i32,  # days since epoch
    :time => :i32,  # microseconds since midnight
    Ecto.UUID => :uuid
  }
  
  def map_ecto_type(ecto_type) do
    Map.get(@type_map, ecto_type, :string)
  end
  
  def infer_from_ecto_schema(module) do
    if function_exported?(module, :__schema__, 1) do
      module.__schema__(:fields)
      |> Enum.map(fn field_name ->
        ecto_type = module.__schema__(:type, field_name)
        gridcodec_type = map_ecto_type(ecto_type)
        {field_name, gridcodec_type}
      end)
    else
      []
    end
  end
end
```

#### 4. Generated Functions

Each derived struct gets these functions:

```elixir
defmodule MyApp.User do
  # ... @derive ...
  
  # Generated by GridCodec.Struct.Compiler
  
  @doc "Returns the GridCodec schema metadata"
  def __gridcodec_schema__, do: %{...}
  
  @doc "Returns template ID for dispatch"
  def __gridcodec_template_id__, do: 1
  
  @doc "Returns schema ID"
  def __gridcodec_schema_id__, do: 0
  
  @doc "Encodes struct to binary (payload only)"
  def __gridcodec_encode__(%__MODULE__{} = struct), do: ...
  
  @doc "Encodes struct with header for dispatch"
  def __gridcodec_encode_framed__(%__MODULE__{} = struct), do: ...
  
  @doc "Decodes binary to struct"
  def __gridcodec_decode__(binary), do: ...
  
  @doc "Wraps binary for zero-copy access"
  def __gridcodec_wrap__(binary), do: ...
  
  @doc "Gets field from wrapped binary"
  def __gridcodec_get__(env, field), do: ...
end
```

#### 5. Usage Examples

```elixir
# Simple struct
defmodule Order do
  @derive {GridCodec.Struct, 
    template_id: 1,
    fields: [
      order_id: :uuid,
      price: :u64,
      quantity: :u32,
      status: :u8
    ]
  }
  
  defstruct [:order_id, :price, :quantity, :status, :_internal]
end

# Ecto schema with inferred types
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  
  @derive {GridCodec.Struct,
    template_id: 2,
    schema_id: 100,
    only: [:id, :name, :email, :inserted_at]
  }
  
  schema "users" do
    field :name, :string
    field :email, :string
    field :password_hash, :string  # excluded
    timestamps()
  end
end

# Using the protocol
order = %Order{order_id: uuid, price: 100, quantity: 5, status: 1}

# Encode via protocol
binary = GridCodec.Encodable.encode(order)
framed = GridCodec.Encodable.encode_framed(order)

# Or via module functions
binary = Order.__gridcodec_encode__(order)

# Decode
{:ok, %Order{} = decoded} = Order.__gridcodec_decode__(binary)

# Zero-copy access
env = Order.__gridcodec_wrap__(binary)
price = Order.__gridcodec_get__(env, :price)
```

---

## Part 2: Pluggable Backends

### Motivation

Different use cases require different serialization formats:
- **Binary (GridCodec)**: Maximum performance, zero-copy access
- **JSON**: Human-readable, web APIs, debugging
- **Protobuf**: Cross-language compatibility
- **MessagePack**: Compact binary, good tooling

Users should be able to switch formats without changing their domain code.

### Design

#### 1. Backend Behaviour

```elixir
defmodule GridCodec.Backend do
  @moduledoc """
  Behaviour for serialization backends.
  
  Each backend implements encoding, decoding, and (optionally) 
  lazy access operations. The backend determines the wire format
  while GridCodec provides the schema and interface.
  """
  
  @type schema :: %{
    fields: [{atom(), atom(), module(), keyword()}],
    groups: list(),
    version: pos_integer(),
    template_id: non_neg_integer(),
    schema_id: non_neg_integer(),
    block_length: non_neg_integer()
  }
  
  @type envelope :: term()  # Backend-specific wrapped data
  
  @doc """
  Encodes a map/struct to binary according to the schema.
  """
  @callback encode(data :: map(), schema :: schema()) :: binary()
  
  @doc """
  Decodes binary to a map according to the schema.
  """
  @callback decode(binary :: binary(), schema :: schema()) :: 
    {:ok, map()} | {:error, term()}
  
  @doc """
  Wraps binary for lazy access (if supported).
  Returns {:ok, envelope} or {:error, :not_supported}.
  """
  @callback wrap(binary :: binary(), schema :: schema()) :: 
    {:ok, envelope()} | {:error, :not_supported}
  
  @doc """
  Gets a field from wrapped data (if supported).
  """
  @callback get(envelope :: envelope(), field :: atom(), schema :: schema()) :: 
    {:ok, term()} | {:error, :not_supported}
  
  @doc """
  Updates a field in the data, returning new binary.
  """
  @callback update(binary :: binary(), field :: atom(), value :: term(), schema :: schema()) ::
    {:ok, binary()} | {:error, term()}
  
  @doc """
  Returns capabilities of this backend.
  """
  @callback capabilities() :: %{
    lazy_access: boolean(),
    pattern_match: boolean(),
    zero_copy: boolean(),
    human_readable: boolean()
  }
  
  @doc """
  Returns the content type for this format.
  """
  @callback content_type() :: String.t()
  
  @optional_callbacks [wrap: 2, get: 3, update: 4]
end
```

#### 2. Built-in Backends

##### Binary Backend (Default)

```elixir
defmodule GridCodec.Backends.Binary do
  @moduledoc """
  The native GridCodec binary format.
  
  This is the default backend providing:
  - Zero-copy field access
  - Sub-binary sharing
  - O(1) fixed-field access
  - Pattern matching support
  """
  @behaviour GridCodec.Backend
  
  @impl true
  def capabilities do
    %{
      lazy_access: true,
      pattern_match: true,
      zero_copy: true,
      human_readable: false
    }
  end
  
  @impl true
  def content_type, do: "application/x-gridcodec"
  
  @impl true
  def encode(data, schema) do
    # Existing GridCodec binary encoding
    GridCodec.Backends.Binary.Encoder.encode(data, schema)
  end
  
  @impl true
  def decode(binary, schema) do
    GridCodec.Backends.Binary.Decoder.decode(binary, schema)
  end
  
  @impl true
  def wrap(binary, schema) do
    {:ok, %GridCodec.Envelope{binary: binary, schema: schema}}
  end
  
  @impl true
  def get(envelope, field, schema) do
    value = GridCodec.Backends.Binary.Getter.get(envelope, field, schema)
    {:ok, value}
  end
  
  @impl true
  def update(binary, field, value, schema) do
    GridCodec.Backends.Binary.Updater.update(binary, field, value, schema)
  end
end
```

##### JSON Backend

```elixir
defmodule GridCodec.Backends.JSON do
  @moduledoc """
  JSON serialization backend using Jason.
  
  Provides human-readable output at the cost of:
  - No zero-copy access (must parse entire document)
  - No pattern matching
  - Larger payload size
  
  Useful for:
  - API responses
  - Debugging
  - Log output
  - Cross-platform compatibility
  """
  @behaviour GridCodec.Backend
  
  @impl true
  def capabilities do
    %{
      lazy_access: false,
      pattern_match: false,
      zero_copy: false,
      human_readable: true
    }
  end
  
  @impl true
  def content_type, do: "application/json"
  
  @impl true
  def encode(data, schema) do
    # Convert types that JSON doesn't support natively
    json_data = prepare_for_json(data, schema)
    Jason.encode!(json_data)
  end
  
  @impl true
  def decode(binary, schema) do
    case Jason.decode(binary) do
      {:ok, json_data} ->
        data = restore_from_json(json_data, schema)
        {:ok, data}
      {:error, _} = error ->
        error
    end
  end
  
  @impl true
  def wrap(binary, schema) do
    # JSON supports lazy access via streaming parsers
    # but for simplicity, we just decode
    case decode(binary, schema) do
      {:ok, data} -> {:ok, %{data: data, schema: schema}}
      error -> error
    end
  end
  
  @impl true
  def get(%{data: data}, field, _schema) do
    {:ok, Map.get(data, field)}
  end
  
  @impl true
  def update(binary, field, value, schema) do
    with {:ok, data} <- decode(binary, schema) do
      updated = Map.put(data, field, value)
      {:ok, encode(updated, schema)}
    end
  end
  
  # Handle UUID, DateTime, etc.
  defp prepare_for_json(data, schema) do
    Enum.reduce(schema.fields, data, fn {name, type, _module, _opts}, acc ->
      value = Map.get(acc, name)
      json_value = type_to_json(value, type)
      Map.put(acc, name, json_value)
    end)
  end
  
  defp type_to_json(nil, _type), do: nil
  defp type_to_json(<<_::128>> = uuid, :uuid), do: Base.encode16(uuid, case: :lower)
  defp type_to_json(%DateTime{} = dt, _), do: DateTime.to_iso8601(dt)
  defp type_to_json(value, _type), do: value
  
  defp restore_from_json(data, schema) do
    Enum.reduce(schema.fields, %{}, fn {name, type, _module, _opts}, acc ->
      string_key = Atom.to_string(name)
      json_value = Map.get(data, string_key)
      value = json_to_type(json_value, type)
      Map.put(acc, name, value)
    end)
  end
  
  defp json_to_type(nil, _type), do: nil
  defp json_to_type(hex, :uuid) when is_binary(hex), do: Base.decode16!(hex, case: :mixed)
  defp json_to_type(iso, :timestamp_us) when is_binary(iso) do
    {:ok, dt, _} = DateTime.from_iso8601(iso)
    dt
  end
  defp json_to_type(value, _type), do: value
end
```

##### MessagePack Backend

```elixir
defmodule GridCodec.Backends.MessagePack do
  @moduledoc """
  MessagePack serialization using Msgpax.
  
  A good middle-ground between binary and JSON:
  - More compact than JSON
  - Better tooling than raw binary
  - Cross-platform support
  """
  @behaviour GridCodec.Backend
  
  @impl true
  def capabilities do
    %{
      lazy_access: false,
      pattern_match: false,
      zero_copy: false,
      human_readable: false
    }
  end
  
  @impl true
  def content_type, do: "application/msgpack"
  
  @impl true
  def encode(data, schema) do
    prepared = prepare_for_msgpack(data, schema)
    Msgpax.pack!(prepared, iodata: false)
  end
  
  @impl true
  def decode(binary, schema) do
    case Msgpax.unpack(binary) do
      {:ok, data} -> {:ok, restore_from_msgpack(data, schema)}
      {:error, _} = error -> error
    end
  end
  
  # ... similar helper functions
end
```

#### 3. Codec Integration

Update the main GridCodec module to support backends:

```elixir
defmodule GridCodec do
  defmacro __using__(opts \\ []) do
    backend = Keyword.get(opts, :backend, GridCodec.Backends.Binary)
    
    quote do
      import GridCodec, only: [defcodec: 1, field: 2, field: 3, group: 2, group: 3]
      
      @gridcodec_opts unquote(opts)
      @gridcodec_backend unquote(backend)
      
      Module.register_attribute(__MODULE__, :gridcodec_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :gridcodec_groups, accumulate: true)
    end
  end
end
```

#### 4. Unified Interface Module

A facade that works with any backend:

```elixir
defmodule GridCodec.Unified do
  @moduledoc """
  Unified interface for working with GridCodec data across backends.
  
  This module provides a consistent API regardless of the underlying
  serialization format. Use this when you want backend-agnostic code.
  
  ## Example
  
      # Works with any backend
      alias GridCodec.Unified, as: GC
      
      # Encode (uses codec's configured backend)
      binary = GC.encode(data, MyCodec)
      
      # Decode
      {:ok, map} = GC.decode(binary, MyCodec)
      
      # Lazy access (falls back to decode if not supported)
      {:ok, env} = GC.wrap(binary, MyCodec)
      value = GC.get(env, :field_name, MyCodec)
      
      # Convert between formats
      json = GC.transcode(binary, MyCodec, to: :json)
  """
  
  @type codec :: module()
  @type envelope :: term()
  
  @doc """
  Encodes data using the codec's configured backend.
  """
  @spec encode(map(), codec()) :: binary()
  def encode(data, codec) do
    backend = codec.__gridcodec_backend__()
    schema = codec.__schema__()
    backend.encode(data, schema)
  end
  
  @doc """
  Encodes with message header for dispatch.
  """
  @spec encode_framed(map(), codec()) :: binary()
  def encode_framed(data, codec) do
    backend = codec.__gridcodec_backend__()
    schema = codec.__schema__()
    header = GridCodec.Header.encode(schema)
    payload = backend.encode(data, schema)
    <<header::binary, payload::binary>>
  end
  
  @doc """
  Decodes binary using the codec's configured backend.
  """
  @spec decode(binary(), codec()) :: {:ok, map()} | {:error, term()}
  def decode(binary, codec) do
    backend = codec.__gridcodec_backend__()
    schema = codec.__schema__()
    backend.decode(binary, schema)
  end
  
  @doc """
  Wraps binary for lazy access if supported, otherwise decodes.
  """
  @spec wrap(binary(), codec()) :: {:ok, envelope()} | {:error, term()}
  def wrap(binary, codec) do
    backend = codec.__gridcodec_backend__()
    schema = codec.__schema__()
    
    case backend.wrap(binary, schema) do
      {:ok, _} = result -> result
      {:error, :not_supported} ->
        # Fallback: decode and wrap in a simple map
        case backend.decode(binary, schema) do
          {:ok, data} -> {:ok, %{__decoded__: data, __codec__: codec}}
          error -> error
        end
    end
  end
  
  @doc """
  Gets a field from wrapped data.
  """
  @spec get(envelope(), atom(), codec()) :: term()
  def get(%{__decoded__: data}, field, _codec) do
    Map.get(data, field)
  end
  
  def get(envelope, field, codec) do
    backend = codec.__gridcodec_backend__()
    schema = codec.__schema__()
    
    case backend.get(envelope, field, schema) do
      {:ok, value} -> value
      {:error, :not_supported} ->
        # Fallback: decode and get
        {:ok, data} = backend.decode(envelope.binary, schema)
        Map.get(data, field)
    end
  end
  
  @doc """
  Transcodes data from one format to another.
  """
  @spec transcode(binary(), codec(), keyword()) :: binary()
  def transcode(binary, codec, opts) do
    to_backend = Keyword.fetch!(opts, :to) |> resolve_backend()
    schema = codec.__schema__()
    
    # Decode with current backend, encode with target
    from_backend = codec.__gridcodec_backend__()
    {:ok, data} = from_backend.decode(binary, schema)
    to_backend.encode(data, schema)
  end
  
  defp resolve_backend(:binary), do: GridCodec.Backends.Binary
  defp resolve_backend(:json), do: GridCodec.Backends.JSON
  defp resolve_backend(:msgpack), do: GridCodec.Backends.MessagePack
  defp resolve_backend(module) when is_atom(module), do: module
end
```

#### 5. Runtime Backend Selection

For cases where the backend needs to be selected at runtime:

```elixir
defmodule GridCodec.Dynamic do
  @moduledoc """
  Runtime backend selection for GridCodec.
  
  Use when the serialization format is determined at runtime
  (e.g., content negotiation in APIs).
  
  ## Example
  
      # In a Phoenix controller
      def create(conn, params) do
        format = get_format(conn)  # :json, :binary, :msgpack
        
        data = build_response(params)
        binary = GridCodec.Dynamic.encode(data, MyCodec, backend: format)
        
        conn
        |> put_resp_content_type(content_type(format))
        |> send_resp(200, binary)
      end
  """
  
  def encode(data, codec, opts \\ []) do
    backend = resolve_backend(opts[:backend] || :binary)
    schema = codec.__schema__()
    backend.encode(data, schema)
  end
  
  def decode(binary, codec, opts \\ []) do
    backend = resolve_backend(opts[:backend] || :binary)
    schema = codec.__schema__()
    backend.decode(binary, schema)
  end
  
  defp resolve_backend(:binary), do: GridCodec.Backends.Binary
  defp resolve_backend(:json), do: GridCodec.Backends.JSON
  defp resolve_backend(:msgpack), do: GridCodec.Backends.MessagePack
  defp resolve_backend(module), do: module
end
```

---

## Part 3: Putting It Together

### Complete Example

```elixir
# 1. Define an Ecto schema with GridCodec derive
defmodule MyApp.Orders.Order do
  use Ecto.Schema
  
  @derive {GridCodec.Struct,
    template_id: 1,
    schema_id: 100,
    version: 1,
    only: [:id, :user_id, :total_cents, :status, :inserted_at],
    # Override inferred types if needed
    field_types: %{
      total_cents: :i64,
      status: {:enum, MyApp.OrderStatus}
    }
  }
  
  schema "orders" do
    field :user_id, :binary_id
    field :total_cents, :integer
    field :status, Ecto.Enum, values: [:pending, :filled, :cancelled]
    field :notes, :string  # excluded from codec
    timestamps()
  end
end

# 2. Use with default binary backend (zero-copy, max performance)
order = %MyApp.Orders.Order{
  id: Ecto.UUID.generate(),
  user_id: user_id,
  total_cents: 5000,
  status: :pending,
  inserted_at: DateTime.utc_now()
}

# Via protocol
binary = GridCodec.Encodable.encode(order)

# Via module
binary = MyApp.Orders.Order.__gridcodec_encode__(order)

# 3. Zero-copy access (binary backend only)
env = MyApp.Orders.Order.__gridcodec_wrap__(binary)
total = MyApp.Orders.Order.__gridcodec_get__(env, :total_cents)

# 4. Transcode to JSON for API response
json = GridCodec.Unified.transcode(binary, MyApp.Orders.Order, to: :json)
# => {"id":"abc-123","user_id":"def-456","total_cents":5000,"status":"pending",...}

# 5. Define explicit codec with JSON backend for a specific use case
defmodule MyApp.Api.OrderResponse do
  use GridCodec,
    backend: GridCodec.Backends.JSON,
    template_id: 1,
    schema_id: 200
  
  defcodec do
    field :id, :uuid
    field :total_cents, :i64
    field :status, :string
  end
end
```

### Phoenix Integration Example

```elixir
# In your endpoint or controller
defmodule MyAppWeb.OrderController do
  use MyAppWeb, :controller
  
  alias GridCodec.Dynamic
  alias MyApp.Orders.Order
  
  def show(conn, %{"id" => id}) do
    order = Orders.get_order!(id)
    
    # Content negotiation
    format = case get_req_header(conn, "accept") do
      ["application/x-gridcodec" | _] -> :binary
      ["application/msgpack" | _] -> :msgpack
      _ -> :json
    end
    
    backend = resolve_backend(format)
    binary = Dynamic.encode(order, Order, backend: format)
    
    conn
    |> put_resp_content_type(backend.content_type())
    |> send_resp(200, binary)
  end
  
  def create(conn, params) do
    # Decode incoming data based on content type
    format = case get_req_header(conn, "content-type") do
      ["application/x-gridcodec" | _] -> :binary
      ["application/msgpack" | _] -> :msgpack
      _ -> :json
    end
    
    body = read_body(conn)
    {:ok, data} = Dynamic.decode(body, Order, backend: format)
    
    # Process order...
  end
end
```

### PubSub Fan-out Example

```elixir
defmodule MyApp.Events do
  @moduledoc """
  Event broadcasting with format flexibility.
  """
  
  # Internal cluster communication uses binary (zero-copy)
  def broadcast_internal(event) do
    binary = GridCodec.Encodable.encode(event)
    Phoenix.PubSub.broadcast(MyApp.PubSub, topic(event), {:event, binary})
  end
  
  # External webhooks use JSON
  def broadcast_webhook(event) do
    json = GridCodec.Unified.transcode(
      GridCodec.Encodable.encode(event),
      event.__struct__,
      to: :json
    )
    
    WebhookSender.send(json)
  end
end
```

---

## Migration Path

### From Plain Structs

```elixir
# Before
defmodule MyApp.Order do
  defstruct [:id, :price, :quantity]
end

# After - just add @derive
defmodule MyApp.Order do
  @derive {GridCodec.Struct,
    fields: [id: :uuid, price: :u64, quantity: :u32]
  }
  defstruct [:id, :price, :quantity]
end
```

### From Explicit Codecs

```elixir
# Before - separate codec module
defmodule MyApp.Codecs.Order do
  use GridCodec
  
  defcodec do
    field :id, :uuid
    field :price, :u64
  end
end

defmodule MyApp.Order do
  defstruct [:id, :price]
end

# After - derive on the struct itself
defmodule MyApp.Order do
  @derive {GridCodec.Struct,
    fields: [id: :uuid, price: :u64]
  }
  defstruct [:id, :price]
end

# Or keep both if you need the explicit codec for special cases
```

### From JSON/Jason

```elixir
# Before
defmodule MyApp.Order do
  @derive {Jason.Encoder, only: [:id, :price]}
  defstruct [:id, :price, :internal]
end

# After - add GridCodec derive alongside Jason
defmodule MyApp.Order do
  @derive {Jason.Encoder, only: [:id, :price]}
  @derive {GridCodec.Struct,
    fields: [id: :uuid, price: :u64]
  }
  defstruct [:id, :price, :internal]
end
```

---

## Implementation Phases

### Phase 1: Backend Abstraction
1. Define `GridCodec.Backend` behaviour
2. Extract current binary encoding into `GridCodec.Backends.Binary`
3. Update compiler to use backend indirection
4. Add backend option to `use GridCodec`

### Phase 2: Additional Backends
1. Implement `GridCodec.Backends.JSON`
2. Implement `GridCodec.Backends.MessagePack`
3. Add `GridCodec.Unified` facade
4. Add `GridCodec.Dynamic` for runtime selection

### Phase 3: Derive Support
1. Define `GridCodec.Encodable` protocol
2. Implement `GridCodec.Struct` derive module
3. Add Ecto type inference
4. Generate codec functions on derived structs

### Phase 4: Advanced Features
1. Pattern matching support across backends (where possible)
2. Lazy JSON parsing (SAX-style) for `wrap`
3. Protobuf backend
4. Schema migration tools

---

## Open Questions

1. **Should derive generate a separate codec module or embed in the struct module?**
   - Embedding is simpler but may bloat the struct module
   - Separate module matches current pattern but adds complexity

2. **How to handle groups in derive?**
   - Groups require entry encoder/decoder functions
   - Could use nested struct derives

3. **Should backends be optional dependencies?**
   - Jason, Msgpax are already common deps
   - Could check `Code.ensure_loaded?/1` at compile time

4. **Pattern matching for non-binary backends?**
   - JSON can't pattern match like binary
   - Could compile to guard-based matching

---

## Summary

This RFC proposes:

1. **`@derive GridCodec.Struct`** - Automatic codec generation for structs with Ecto integration
2. **`GridCodec.Backend` behaviour** - Pluggable serialization formats
3. **Built-in backends** - Binary (default), JSON, MessagePack
4. **Unified interface** - `GridCodec.Unified` for backend-agnostic code

Together these enable seamless adoption while preserving GridCodec's performance benefits where they matter most.


