defmodule GridCodec.Struct do
  @moduledoc """
  Integrates GridCodec with Elixir structs.

  When you `use GridCodec.Struct`, the `defcodec/1` macro becomes available
  and automatically generates both the struct definition and the codec
  implementation.

  ## Features

  - **Auto-generated `defstruct`**: Field definitions in `defcodec` become struct fields
  - **Enforced keys**: Fields with `presence: :required` are added to `@enforce_keys`
  - **Compile-time registration**: Codecs register for dispatch via template_id/schema_id
  - **Zero-copy access**: Use `get/2` macro for O(1) field access without full decode

  ## Quick Example

      defmodule MyApp.Order do
        use GridCodec.Struct, template_id: 1, schema_id: 100

        defcodec do
          field :id, :uuid, presence: :required
          field :price, :u64, default: 0
          field :quantity, :u32
        end
      end

      # Creates:
      # - %MyApp.Order{} struct with @enforce_keys [:id]
      # - MyApp.Order.encode/1, decode/1
      # - MyApp.Order.get/2 macro for zero-copy field access
      # - Registered for dispatch via GridCodec.decode/1

  ## From .grid Schema File

  You can also define your codec from a `.grid` schema file:

      # priv/schemas/trading.grid
      schema Trading {
        id: 100
        version: 1
      }

      message Order (1001) {
        id: uuid_string
        price: u64
        quantity: u32
      }

      # lib/my_app/order.ex
      defmodule MyApp.Order do
        use GridCodec.Struct,
          grid_file: "priv/schemas/trading.grid",
          message: :Order

        # You can add custom functions here
        def validate(%__MODULE__{quantity: q}) when q > 0, do: :ok
        def validate(_), do: {:error, :invalid}
      end

  ## Options

  - `:template_id` - Unique message type identifier (default: hash of module name)
  - `:schema_id` - Schema namespace identifier (default: 0)
  - `:version` - Schema version (default: 1)
  - `:name` - Stable type name for serialization (default: full module path, e.g.,
    `"MyApp.Events.OrderSubmitted"`). Set explicitly for short names.
    Used by `__type__/0` and `GridCodec.Registry.lookup_by_type/1` for EventStore integration.
  - `:endian` - Byte order, `:little` or `:big` (default: `:little`)
  - `:align` - Enable field alignment (default: false)
  - `:generate_typespec` - Auto-generate `t()`, `layout()`, and `framed_layout()` types (default: true)
  - `:validate` - Enable type-level validation before encoding (default: `false`).
    Catches integer overflow, type mismatches, and invalid formats with structured
    `GridCodec.ValidationError`. Zero overhead when disabled.
  - `:telemetry` - Emit `[:grid_codec, :encode]` / `[:grid_codec, :decode]` telemetry events
    with duration and byte size (default: `false`). Zero overhead when disabled.
  - `:telemetry_min_duration` - Skip emitting telemetry events when duration is below this
    threshold in `:native` time units (default: `0`, emit all). Filters out cheap operations.
  - `:grid_file` - Path to `.grid` schema file (optional)
  - `:message` - Message name in schema file (required with `:grid_file`)

  Options can also be set globally via application config:

      config :grid_codec,
        telemetry: true,
        telemetry_min_duration: 10_000

  ## Usage

      defmodule MyApp.Trade do
        use GridCodec.Struct,
          template_id: 2,
          schema_id: 100

        defcodec do
          field :trade_id, :uuid, presence: :required
          field :price, :u64
          field :quantity, :u32
          field :side, :u8, default: 0
        end
      end

      # Create and encode
      trade = %MyApp.Trade{
        trade_id: <<1::128>>,
        price: 15000,
        quantity: 100
      }

      # Encode with header (for dispatch)
      {:ok, binary} = GridCodec.encode(trade)
      # or: {:ok, binary} = MyApp.Trade.encode(trade)

      # Decode (dispatch finds correct module)
      {:ok, %MyApp.Trade{}} = GridCodec.decode(binary)
      # or: {:ok, %MyApp.Trade{}} = MyApp.Trade.decode(binary)

      # Zero-copy field access (no full decode!)
      require MyApp.Trade
      price = MyApp.Trade.get(binary, :price)

  ## Template ID

  If not specified, `template_id` defaults to a hash of the module name:

      # These are equivalent:
      use GridCodec.Struct, template_id: :erlang.phash2(MyApp.Order) &&& 0xFFFF
      use GridCodec.Struct  # auto-generates template_id

  For production use, explicit template_ids are recommended for stability.
  """

  @doc false
  defmacro __using__(opts \\ []) do
    grid_file = Keyword.get(opts, :grid_file)
    grid_schema = Keyword.get(opts, :grid_schema)
    message_name = Keyword.get(opts, :message)

    # Handle grid_schema which might be a sigil AST or already-parsed schema
    resolved_schema = resolve_grid_schema(grid_schema)

    cond do
      grid_file ->
        # Load schema from .grid file at compile time
        generate_from_grid_file(grid_file, message_name, opts)

      resolved_schema ->
        # Use inline schema (from sigil or parsed)
        generate_from_schema(resolved_schema, message_name, opts)

      true ->
        # Standard defcodec approach
        quote do
          import GridCodec.Struct, only: [defcodec: 1]
          import GridCodec, only: [field: 2, field: 3, group: 2, group: 3, batch: 2]

          @gridcodec_opts unquote(opts)
          @gridcodec_is_struct true

          Module.register_attribute(__MODULE__, :gridcodec_fields, accumulate: true)
          Module.register_attribute(__MODULE__, :gridcodec_groups, accumulate: true)
          Module.register_attribute(__MODULE__, :gridcodec_batches, accumulate: true)
        end
    end
  end

  # Resolve grid_schema which might be:
  # - nil
  # - A sigil AST like {:sigil_G, _, [[string], []]}
  # - An already-parsed schema struct
  defp resolve_grid_schema(nil), do: nil

  defp resolve_grid_schema(%GridCodec.Schema.Parser.Schema{} = schema), do: schema

  defp resolve_grid_schema({:sigil_G, _meta, [{:<<>>, _, [string]}, []]})
       when is_binary(string) do
    case GridCodec.Schema.Parser.parse(string) do
      {:ok, schema} -> schema
      {:error, reason} -> raise ArgumentError, "Invalid grid schema: #{inspect(reason)}"
    end
  end

  defp resolve_grid_schema({:sigil_g, _meta, [{:<<>>, _, [string]}, []]})
       when is_binary(string) do
    case GridCodec.Schema.Parser.parse(string) do
      {:ok, schema} -> schema
      {:error, reason} -> raise ArgumentError, "Invalid grid schema: #{inspect(reason)}"
    end
  end

  defp resolve_grid_schema(other) do
    raise ArgumentError,
          "Invalid grid_schema option. Expected ~G sigil or parsed schema, got: #{inspect(other)}"
  end

  defp generate_from_grid_file(grid_file, message_name, opts) do
    case GridCodec.Schema.Parser.parse_file_with_imports(grid_file) do
      {:ok, schema} ->
        generate_from_schema(schema, message_name, opts)

      {:error, {:file_error, path, reason}} ->
        raise ArgumentError,
              "Could not read grid file #{path}: #{inspect(reason)}"

      {:error, reason} ->
        raise ArgumentError,
              "Could not parse grid file #{grid_file}: #{inspect(reason)}"
    end
  end

  defp generate_from_schema(schema, struct_name, opts) do
    structs = Map.get(schema, :structs) || %{}
    struct_def = Map.get(structs, struct_name)

    if struct_def do
      generate_from_struct_def(schema, struct_def, opts)
    else
      available = Map.keys(structs) |> Enum.join(", ")

      raise ArgumentError,
            "Struct :#{struct_name} not found in schema. " <>
              "Available structs: #{available}"
    end
  end

  defp generate_from_struct_def(schema, struct_def, opts) do
    custom_types = build_custom_types(schema, opts)
    field_defs = Enum.map(struct_def.fields, &grid_field_to_def(&1, custom_types))

    group_defs =
      Enum.map(struct_def.groups, fn group ->
        group_fields = Enum.map(group.fields, &grid_field_to_def(&1, custom_types))
        {group.name, group_fields, []}
      end)

    version = struct_def.version || schema.version || 1

    merged_opts =
      opts
      |> Keyword.put_new(:template_id, struct_def.template_id)
      |> Keyword.put_new(:schema_id, schema.id || 0)
      |> Keyword.put_new(:version, version)
      |> Keyword.delete(:grid_file)
      |> Keyword.delete(:grid_schema)
      |> Keyword.delete(:message)
      |> Keyword.delete(:types)

    quote do
      import GridCodec.Struct, only: [defcodec: 1]
      import GridCodec, only: [field: 2, field: 3, group: 2, group: 3, batch: 2]

      @gridcodec_opts unquote(Macro.escape(merged_opts))
      @gridcodec_is_struct true

      Module.register_attribute(__MODULE__, :gridcodec_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :gridcodec_groups, accumulate: true)
      Module.register_attribute(__MODULE__, :gridcodec_batches, accumulate: true)

      for {name, type, field_opts} <- unquote(Macro.escape(field_defs)) do
        @gridcodec_fields {name, type, field_opts}
      end

      for {name, fields, group_opts} <- unquote(Macro.escape(group_defs)) do
        @gridcodec_groups {name, fields, group_opts}
      end

      @before_compile GridCodec.Struct.Compiler
    end
  end

  defp build_custom_types(schema, opts) do
    explicit = Keyword.get(opts, :types, %{})

    auto_resolved =
      schema.enums
      |> Enum.reduce(%{}, fn {name, _enum_def}, acc ->
        if Map.has_key?(explicit, name) do
          acc
        else
          case auto_resolve_enum(name) do
            {:ok, module} -> Map.put(acc, name, module)
            :error -> acc
          end
        end
      end)

    Map.merge(auto_resolved, explicit)
  end

  defp auto_resolve_enum(name) do
    name_str = Atom.to_string(name)

    if Code.ensure_loaded?(GridCodec.Registry) and
         function_exported?(GridCodec.Registry, :lookup_enum_by_name, 1) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(GridCodec.Registry, :lookup_enum_by_name, [name_str])
    else
      :error
    end
  end

  defp grid_field_to_def(field, custom_types) do
    type_spec =
      if field.type_params != [] do
        resolved = Map.get(custom_types, field.type, field.type)
        {resolved, field.type_params}
      else
        Map.get(custom_types, field.type, field.type)
      end

    field_opts =
      []
      |> maybe_put(:presence, field.presence)
      |> maybe_put(:wire_format, field.wire_format)
      |> maybe_put(:since, field.since)
      |> maybe_put(:default, field.default)
      |> maybe_put(:value, field.value)

    field_opts =
      if field.optional, do: Keyword.put_new(field_opts, :presence, :optional), else: field_opts

    {field.name, type_spec, field_opts}
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, val), do: Keyword.put(kw, key, val)

  @doc """
  Defines the codec schema and generates both `defstruct` and codec functions.

  Inside the `defcodec` block, use `field/2`, `field/3`, and `group/2`
  to define your struct fields and binary layout.

  ## Example

      defcodec do
        field :id, :uuid, presence: :required
        field :price, :u64, default: 0
        field :quantity, :u32
      end

  ## Generated Struct

  The `defstruct` is generated automatically with:
  - Field names from `field` declarations
  - Default values from the `:default` option
  - Fields with `presence: :required` added to `@enforce_keys`
  - Fields with `presence: :constant` get their `:value` as default

  ## Generated Functions

  - `encode/1,2` - Encodes struct to binary, returns `{:ok, binary} | {:error, ValidationError.t()}`
  - `decode/1,2` - Decodes binary to struct (expects header by default)
  - `get/2,3` macro - Zero-copy field access via binary pattern matching
  - `match/1,2` macro - Multi-field pattern matching
  - `field/1` macro - Returns field spec for `GridCodec.get/2`
  - `__schema__/0` - Returns schema metadata
  - `__template_id__/0` - Returns template ID
  - `__schema_id__/0` - Returns schema ID
  - `__type__/0` - Returns the stable type name (from `:name` option or module name)
  - `__fields__/0` - Returns list of field names

  ## Generated Types

  By default, `GridCodec.Struct` also emits:

  - `@type t() :: %__MODULE__{}` - Struct type
  - `@type layout()` - Wire layout payload type (`header: false`)
  - `@type framed_layout()` - Wire layout including 8-byte GridCodec header

  Pass `generate_typespec: false` to disable automatic type generation.
  """
  defmacro defcodec(do: block) do
    quote do
      # Collect field definitions
      unquote(block)

      # Generate the struct and codec implementation
      @before_compile GridCodec.Struct.Compiler
    end
  end
end
