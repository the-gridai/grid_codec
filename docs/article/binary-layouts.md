# Binary Layouts for Elixir

## What

A binary layout is a module-typed binary with named fields at compile-time-known offsets. At runtime it's a plain `binary()`. The compiler knows the size, offsets, types, and endianness of every field.

```elixir
deflayout ChatMessage do
  field :message_id, :u64
  field :channel_id, :u64
  field :author_id, :u64
  field :status, :u8
  field :flags, :u16
  field :counter, :u32
  field :timestamp, :timestamp_us
end
```

Custom types (decimals, enums, UUIDs) work the same way — each type module defines its binary encoding. The compiler uses type metadata to encode literals in patterns and decode values on extraction.

`ChatMessage.t()` is a type. The runtime value is `binary()`. No wrapper term, no allocation, no new data type in the VM.

## Why

Elixir has the best binary pattern matching of any high-level language. But binary schemas are not reusable. Every module that reads a binary protocol re-derives the field offsets, segment sizes, and endianness from scratch. There is no way to name a binary structure, reference it in a type, or compose it across modules.

Structs solve this for Erlang terms. Layouts solve it for binaries.

## Pattern matching

Match on layout fields by name, in any order. The compiler canonicalizes to optimal physical order and emits a single `<<...>>` pattern.

```elixir
def handle(%ChatMessage<<author_id: uid, status: 1>>, _metadata) do
  {:streaming, uid}
end

def handle(%ChatMessage<<status: 2>>, _metadata), do: :complete
def handle(_, _), do: :ok
```

These are equivalent and compile identically:

```elixir
%ChatMessage<<status: s, author_id: a>>
%ChatMessage<<author_id: a, status: s>>
```

Matching a single late field skips earlier bytes:

```elixir
%ChatMessage<<status: s>>
# compiles to: <<_::binary-size(offset), s::8, _::binary>>
```

Guards work:

```elixir
def rate_limited?(%ChatMessage<<rate_remaining: r>>) when r == 0, do: true
def rate_limited?(_), do: false
```

## Pin operator

```elixir
expected = 2
case bin do
  %ChatMessage<<status: ^expected>> -> :match
end
```

The pinned variable is compared against the raw bytes at the field's offset. For primitive types (integers, bools), this works directly. For custom types that have a non-trivial binary encoding, the compiler encodes the pinned value before the match — the same way `~r//` compiles a regex pattern at compile time rather than at match time.

## Construction

```elixir
msg = %ChatMessage<<
  message_id: 1,
  channel_id: 42,
  author_id: 7,
  status: 1,
  flags: 0,
  counter: 0,
  timestamp: System.system_time(:microsecond)
>>
```

Compiles to a single `<<...>>` binary construction with fields encoded at their declared offsets. Missing fields use defaults or null sentinels.

## Field update

```elixir
msg2 = %{msg | status: 2, flags: 7}
```

Today this copies the entire binary. With native layout support, the compiler's alias analysis (the same pass that enables destructive tuple update in OTP 27) could detect when the binary is unique and write directly to the field's byte offset — O(1) regardless of binary size.

## Field access

```elixir
msg.status      # reads 1 byte at offset N
msg.counter     # reads 4 bytes at offset M
msg.author_id   # reads 8 bytes at offset K
```

Each access compiles to a binary pattern match at a known offset. No match context allocation needed — the compiler emits a direct indexed load.

## Type

```elixir
@type t() :: %__MODULE__<<>>
```

`ChatMessage.t()` is a subtype of `binary()`. Two different layout types never overlap — `ChatMessage.t()` intersects `TypingEvent.t()` to `none()`. This is a closed type, and Elixir's set-theoretic type engine handles closed intersections efficiently (see [eager literal intersections](https://elixir-lang.org/blog/2026/02/26/eager-literal-intersections/)).

Exhaustive dispatch:

```elixir
@spec handle(ChatMessage.t() | TypingEvent.t()) :: :ok
def handle(%ChatMessage<<status: s>>), do: process_chat(s)
def handle(%TypingEvent<<user_id: u>>), do: process_typing(u)
# compiler warns if a variant is unhandled
```

## What this enables in the VM

The compiler and JIT gain optimization opportunities that are impossible with opaque `binary()`:

- **Direct indexed load** for field access — skip match context setup
- **Destructive binary update** — in-place write when refcount is 1 (extending OTP 27's destructive tuple update)
- **Compile-time bounds elimination** — the type proves the binary is the right size
- **SIMD batch filtering** — known offsets enable vectorized field comparison across message batches
- **Zero-cost sub-layouts** — embedded layouts are sub-binary references at known offsets
- **ETF bypass** — for cross-node sends, a layout-typed binary can skip struct serialization

## What this enables in the ecosystem

- **Phoenix.PubSub**: broadcast layout binaries without deep-copying to each subscriber
- **Commanded/EventStore**: event handlers pattern-match on layout fields without decoding unrelated events
- **ThousandIsland/Bandit**: binary protocol handlers with typed field access in function heads
- **LiveView**: state patches as compact layout binaries instead of decoded maps
- **NIF interop**: layout memory matches C struct layout — NIFs read fields by pointer offset

## What works today

I have a prototype implementing the semantics as macros:

```elixir
defmodule ChatMessage do
  use GridCodec.Struct, template_id: 70, schema_id: 400
  defcodec do
    field :status, :u8
    field :author_id, :u64
    # ...
  end
end

# Pattern matching in function heads
defmacrop chat(fields), do: quote(do: ChatMessage.match(unquote(fields)))

def handle(chat(status: 1, author_id: uid), _meta), do: {:streaming, uid}
def handle(_, _), do: :ok
```

The macro compiles to `<<...>>` patterns. Pin operator works for primitive types. Custom type pins require explicit `encode_field/2`. The semantics are identical to the proposed syntax — the gap is:

1. `%Mod<<>>` requires a parser change
2. Auto-encoding pins on custom types in function heads requires compiler support
3. Destructive binary update requires VM support
4. Layout types require integration with the gradual type system

## Prior art

- **Ada**: record representation clauses — bit positions and sizes of fields in records
- **Zig**: `packed struct` / `extern struct` — bit-level and C ABI layout control
- **OCaml**: `cstruct` ppx — C-struct access over buffers (MirageOS network stack)
- **Kaitai Struct**: declarative binary format language, generates parsers for 12+ languages
- **Cap'n Proto**: wire format designed for zero-copy field access
- **Erlang bit syntax**: `<<Value:Size/Type>>` — the foundation layouts build on
