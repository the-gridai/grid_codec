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
  - **Typed groups**: Reuse fixed-size codec structs with `group :name, of: Module`
  - **Runtime lookups**: Generate named alternate access paths over groups and batches with `lookups do`
  - **Validation pipelines**: Compose accumulating struct validations with `validations do`
    / `invariants do`, plus refined custom types for field-local rules
  - **Lifecycle hooks**: Optional `before_encode/2` and `after_decode/2`
    callbacks normalize between runtime structs and persisted wire structs

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

      struct Order (template_id: 1001) {
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

  - `:template_id` - Message type identifier within a schema (default: hash of module name)
  - `:schema_id` - Schema namespace identifier (default: 0 on the wire). Omitted codecs
    still use `0` in the binary header, but are excluded from `mix grid_codec.export`
    until you add `schema_id:` or `schema:`.
  - `:schema` - Schema name (string) that resolves to a numeric `:schema_id` from app config
    at compile time. Requires a `schemas:` entry in the app's `:grid_codec` config.
    Mutually exclusive with `:schema_id`. Raises at compile time if the name is not found.
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
  - `:grid_schema` - Inline `.grid` schema via `~G` / `~g` sigil or parsed schema struct (optional)
  - `:message` - Message name in schema file (required with `:grid_file`)
  - `:types` - Explicit mapping from `.grid` type names to Elixir modules when loading
    from `:grid_file` / `:grid_schema` (optional)
  - `:field_defaults` - A keyword list of default options applied to every `field`
    declaration. Explicit options on individual fields take precedence. Useful when
    most fields share a common option like `presence: :required`.
  - `:doc_examples` - When `true` (default), the compiler emits runnable `iex>` snippets
    in generated `@doc` for `new/1`, `new_binary/1`, `encode/2`, `decode/2`, and
    `validate_struct/1` when the codec shape is supported. Set to `false` to keep
    prose-only docs (for example exotic layouts where deterministic examples are unsafe).

  Options can also be set globally via application config:

      config :grid_codec,
        telemetry: true,
        telemetry_min_duration: 10_000

  ## Named Schemas

  Instead of hardcoding numeric schema IDs, you can reference schemas by name.
  The name is resolved at compile time from the app's `:grid_codec` config:

      # config/config.exs
      config :my_app, :grid_codec,
        schemas: %{100 => "trading"}

      # lib/my_app/trade.ex
      defmodule MyApp.Trade do
        use GridCodec.Struct,
          template_id: 2,
          schema: "trading"

        defcodec do
          field :trade_id, :uuid, presence: :required
          field :price, :u64
        end
      end

      MyApp.Trade.__schema_id__()  #=> 100

  This eliminates magic numbers and gives you compile-time safety — a typo in
  the schema name raises immediately. The same config map is used by
  `mix grid_codec.export`, so there's a single source of truth.

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

  ## Validation Pipelines

  `GridCodec.Struct` also supports accumulating state validations.

      defmodule MyApp.Window do
        use GridCodec.Struct, template_id: 10, validate: true

        defcodec do
          field :start_ns, :timestamp_ns
          field :end_ns, :timestamp_ns
        end

        validations do
          validate compare(:end_ns, :>=, :start_ns),
            name: :end_after_start,
            category: :invariant
        end
      end

  Type validation remains the first gate. Decoded invariants run only after the
  struct is type-safe, so callback validators can assume fields are already in
  their declared domain types and focus on cross-field rules.

  Field-local rules should usually live in a custom type. Cross-field state rules
  belong in the validation pipeline. Command/workflow checks should remain in the
  consuming application.

  ## Identity And Uniqueness

  GridCodec structs have three distinct identifiers, each with a different job:

  - `module` - The Elixir module, such as `MyApp.Events.OrderCreated`. This is
    how code refers to the struct at compile time and runtime.
  - `{schema_id, template_id}` - The wire identity used by framed binaries and
    `GridCodec.decode/1` dispatch. This pair must be unique across all codecs
    that share a dispatch registry. `template_id` alone is only unique within a
    `schema_id`.
  - `name` / `__type__/0` - The logical type name used by
    `GridCodec.Registry.lookup_by_type/1` and integrations like EventStore.
    This is separate from wire dispatch and must be unique only if you rely on
    type-name lookup.

  `version` is not part of identity. It describes schema evolution for a given
  wire type and is validated during decode, but dispatch still starts from the
  `{schema_id, template_id}` pair.

  In practice:

  - Two codecs may share the same `template_id` if their `schema_id`s differ.
  - Two codecs must not share the same `{schema_id, template_id}` pair.
  - Two codecs must not share the same `name` if you want reliable
    `lookup_by_type/1` behavior.

  ## Guarantees And Collisions

  GridCodec provides different levels of protection depending on which identity
  is colliding:

  - `module` redefinition follows normal Elixir semantics. If you define the
    same module twice, Elixir warns and the later definition replaces the
    earlier one in the code server. GridCodec does not add a second layer of
    protection here.
  - `name` / `__type__/0` collisions are rejected at compile time when a codec
    module is defined while another loaded GridCodec struct already claims the
    same type name. The `:grid_codec` Mix compiler also rejects duplicate type
    names across compiled codecs before generating the consolidated registry.
  - `{schema_id, template_id}` collisions are rejected by `GridCodec.Dispatch`
    and by the consolidated `GridCodec.Registry` generation step. In those
    paths, compilation fails because wire dispatch would otherwise be ambiguous.

  `version` does not make `{schema_id, template_id}` unique. Two codecs with
  the same `schema_id` and `template_id` but different versions still collide,
  because dispatch first selects a codec by `{schema_id, template_id}` and only
  then checks version compatibility.

  One caveat: the fallback runtime `GridCodec.Registry` used outside the
  consolidated compiler path is weaker than the compile-time guarantees above.
  If duplicate `{schema_id, template_id}` pairs somehow exist in the loaded code
  set, the fallback registry collapses them into one runtime map entry rather
  than raising immediately. In other words, duplicate wire IDs in the fallback
  path should be treated as undefined behavior, not as a supported versioning
  mechanism.

  ## Template ID

  If not specified, `template_id` defaults to a hash of the module name:

      # These are equivalent:
      use GridCodec.Struct, template_id: :erlang.phash2(MyApp.Order) &&& 0xFFFF
      use GridCodec.Struct  # auto-generates template_id

  For production use, explicit template_ids are recommended for stability.
  The auto-generated value is convenient for local development, but renaming the
  module changes the derived ID.
  """

  @typedoc """
  Result accepted from lifecycle hooks.

  Hooks may return the normalized struct directly, `{:ok, struct}`, or
  `{:error, reason}` to stop the encode/decode operation.
  """
  @type lifecycle_result(struct_type) ::
          struct_type | {:ok, struct_type} | {:error, term()}

  @doc """
  Optional hook invoked before encoding.

  Use this to normalize a runtime struct into the wire-backed shape before
  generated validation and encoding run. The second argument is the target
  header metadata when encoding a framed binary, or `nil` for payload-only
  encoding (`header: false`).
  """
  @callback before_encode(struct(), GridCodec.Header.t() | nil) ::
              lifecycle_result(struct())

  @doc """
  Optional hook invoked after decoding.

  Use this to rebuild derived runtime fields such as indexes or caches from the
  decoded wire fields. The second argument is the decoded header metadata when
  available, or `nil` when decoding payload-only binaries.
  """
  @callback after_decode(struct(), GridCodec.Header.t() | nil) ::
              lifecycle_result(struct())

  @optional_callbacks before_encode: 2, after_decode: 2

  @doc false
  defmacro __using__(opts \\ []) do
    opts = resolve_schema_option(opts)

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
          @behaviour GridCodec.Struct

          import GridCodec.Struct, only: [defcodec: 1]

          import GridCodec,
            only: [
              field: 2,
              field: 3,
              group: 2,
              group: 3,
              batch: 2,
              validations: 1,
              validate: 1,
              validate: 2,
              invariants: 1,
              invariant: 2,
              where: 1,
              lookups: 1,
              lookup: 2,
              views: 1,
              view: 2,
              virtual: 1,
              virtual: 2
            ]

          import GridCodec.Validations,
            only: [compare: 3, compare: 4, present: 1, one_of: 2, one_of: 3]

          @gridcodec_opts unquote(opts)
          @gridcodec_is_struct true

          Module.register_attribute(__MODULE__, :gridcodec_fields, accumulate: true)
          Module.register_attribute(__MODULE__, :gridcodec_groups, accumulate: true)
          Module.register_attribute(__MODULE__, :gridcodec_batches, accumulate: true)
          Module.register_attribute(__MODULE__, :gridcodec_lookups, accumulate: true)
          Module.register_attribute(__MODULE__, :gridcodec_virtuals, accumulate: true)
          Module.register_attribute(__MODULE__, :gridcodec_validations, accumulate: true)
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

        group_opts =
          []
          |> then(fn o -> if group.doc, do: [{:doc, group.doc} | o], else: o end)
          |> then(fn o -> if group.framing, do: [{:framing, group.framing} | o], else: o end)
          |> then(fn o -> if group.of_type, do: [{:of, group.of_type} | o], else: o end)

        {group.name, group_fields, group_opts}
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
      @behaviour GridCodec.Struct

      import GridCodec.Struct, only: [defcodec: 1]

      import GridCodec,
        only: [
          field: 2,
          field: 3,
          group: 2,
          group: 3,
          batch: 2,
          validations: 1,
          validate: 1,
          validate: 2,
          invariants: 1,
          invariant: 2,
          where: 1,
          lookups: 1,
          lookup: 2,
          views: 1,
          view: 2,
          virtual: 1,
          virtual: 2
        ]

      import GridCodec.Validations,
        only: [compare: 3, compare: 4, present: 1, one_of: 2, one_of: 3]

      @gridcodec_opts unquote(Macro.escape(merged_opts))
      @gridcodec_is_struct true

      Module.register_attribute(__MODULE__, :gridcodec_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :gridcodec_groups, accumulate: true)
      Module.register_attribute(__MODULE__, :gridcodec_batches, accumulate: true)
      Module.register_attribute(__MODULE__, :gridcodec_lookups, accumulate: true)
      Module.register_attribute(__MODULE__, :gridcodec_virtuals, accumulate: true)
      Module.register_attribute(__MODULE__, :gridcodec_validations, accumulate: true)

      for {name, type, field_opts} <- unquote(Macro.escape(field_defs)) do
        @gridcodec_fields {name, type, field_opts}
      end

      for {name, fields, group_opts} <- unquote(Macro.escape(group_defs)) do
        @gridcodec_groups {name, fields, group_opts}
      end

      # Define struct immediately so %__MODULE__{} works in subsequent function heads
      {gridcodec_sf__, gridcodec_ek__} =
        GridCodec.Struct.Compiler.compute_struct_fields(
          Module.get_attribute(__MODULE__, :gridcodec_fields) || [],
          Module.get_attribute(__MODULE__, :gridcodec_groups) || [],
          Module.get_attribute(__MODULE__, :gridcodec_batches) || [],
          Module.get_attribute(__MODULE__, :gridcodec_virtuals) || []
        )

      if gridcodec_ek__ != [] do
        @enforce_keys gridcodec_ek__
      end

      defstruct gridcodec_sf__

      @before_compile GridCodec.Struct.Compiler
    end
  end

  defp build_custom_types(schema, opts) do
    explicit = Keyword.get(opts, :types, %{})

    auto_resolved_enums =
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

    auto_resolved_types =
      schema.types
      |> Enum.reduce(%{}, fn {name, _type_def}, acc ->
        if Map.has_key?(explicit, name) do
          acc
        else
          case auto_resolve_custom_type(name) do
            {:ok, module} -> Map.put(acc, name, module)
            :error -> acc
          end
        end
      end)

    auto_resolved_enums
    |> Map.merge(auto_resolved_types)
    |> Map.merge(explicit)
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

  defp auto_resolve_custom_type(name) do
    name_str = Atom.to_string(name)

    if Code.ensure_loaded?(GridCodec.Registry) and
         function_exported?(GridCodec.Registry, :lookup_custom_type_by_name, 1) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(GridCodec.Registry, :lookup_custom_type_by_name, [name_str])
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
      |> maybe_put(:doc, field.doc)
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

  defp resolve_schema_option(opts) do
    schema_name = Keyword.get(opts, :schema)
    schema_id = Keyword.get(opts, :schema_id)

    cond do
      schema_name != nil and schema_id != nil ->
        raise ArgumentError,
              "schema: and schema_id: are mutually exclusive. " <>
                "Got schema: #{inspect(schema_name)}, schema_id: #{inspect(schema_id)}"

      is_binary(schema_name) ->
        resolved_id = resolve_schema_name(schema_name)

        opts
        |> Keyword.delete(:schema)
        |> Keyword.put(:schema_id, resolved_id)

      schema_name != nil ->
        raise ArgumentError,
              "schema: must be a string, got: #{inspect(schema_name)}"

      true ->
        opts
    end
  end

  defp resolve_schema_name(name) do
    schemas = load_schema_config()
    inverted = Map.new(schemas, fn {id, n} -> {n, id} end)

    case Map.get(inverted, name) do
      nil ->
        available = schemas |> Map.values() |> Enum.sort()

        raise ArgumentError,
              "Unknown schema #{inspect(name)}. Available: #{inspect(available)}"

      id ->
        id
    end
  end

  defp load_schema_config do
    app = Mix.Project.config()[:app]
    config = Application.get_env(app, :grid_codec, [])
    Keyword.get(config, :schemas, %{})
  end

  @doc """
  Defines the codec schema and generates both `defstruct` and codec functions.

  Inside the `defcodec` block, use `field/2`, `field/3`, `group/2`,
  `batch/2`, and `lookups/1` to define your struct fields, collection
  sections, and runtime access paths.

  ## Example

      defcodec do
        field :id, :uuid, presence: :required
        field :price, :u64, default: 0
        field :quantity, :u32

        group :fills, of: MyApp.Fill

        lookups do
          lookup :fills_by_id do
            from :fills
            into :map
            key :fill_id
          end
        end
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
  - `lookup/2` - Builds a named runtime lookup for this codec
  - `__schema__/0` - Returns schema metadata
  - `__lookups__/0` / `__lookup__/1` - Returns normalized Elixir-side lookup metadata
  - `__template_id__/0` - Returns template ID
  - `__schema_id__/0` - Returns schema ID
  - `__type__/0` - Returns the stable type name (from `:name` option or module name)
  - `__fields__/0` - Returns list of field names

  ## Runtime Lookups

  Lookups are generated Elixir helpers over decoded `group` and `batch` fields.
  They are not part of the wire format and are not exported to `.grid`.

      defcodec do
        group :reservations, of: MyApp.Reservation

        lookups do
          lookup :reservations_by_id do
            from :reservations
            into :map
            key :reservation_id
          end
        end
      end

      {:ok, account} = MyCodec.decode(binary)
      {:ok, by_id} = MyCodec.reservations_by_id(account)

  Lookups are computed on demand. The decoded struct keeps only the canonical
  source field (`reservations` in the example above), not the derived map.

  ## Generated Types

  By default, `GridCodec.Struct` also emits:

  - `@type t() :: %__MODULE__{}` - Struct type
  - `@type layout()` - Wire layout payload type (`header: false`)
  - `@type framed_layout()` - Wire layout including 8-byte GridCodec header

  Pass `generate_typespec: false` to disable automatic type generation.
  """
  defmacro defcodec(do: block) do
    quote do
      unquote(block)

      # Define struct immediately so %__MODULE__{} works in subsequent function heads.
      # This calls compute_struct_fields as a regular function (not macro expansion),
      # so Module.get_attribute reads the already-accumulated field definitions.
      {gridcodec_sf__, gridcodec_ek__} =
        GridCodec.Struct.Compiler.compute_struct_fields(
          Module.get_attribute(__MODULE__, :gridcodec_fields) || [],
          Module.get_attribute(__MODULE__, :gridcodec_groups) || [],
          Module.get_attribute(__MODULE__, :gridcodec_batches) || [],
          Module.get_attribute(__MODULE__, :gridcodec_virtuals) || [],
          Keyword.get(
            Module.get_attribute(__MODULE__, :gridcodec_opts) || [],
            :field_defaults,
            []
          )
        )

      if gridcodec_ek__ != [] do
        @enforce_keys gridcodec_ek__
      end

      defstruct gridcodec_sf__

      # Generate codec functions (encode/decode/get/etc.) after module body
      @before_compile GridCodec.Struct.Compiler
    end
  end
end
