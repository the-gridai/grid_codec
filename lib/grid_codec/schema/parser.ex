defmodule GridCodec.Schema.Parser do
  @moduledoc """
  Parser for `.grid` schema files.

  ## Format Specification — Syntax 1

  The `.grid` format is a language-neutral schema definition language for
  GridCodec binary codecs. Each file starts with a `@syntax` directive
  declaring the format version. When absent, the parser assumes the latest
  supported syntax.

  ### Directives

      @syntax 1

  Declares the format version. The parser rejects files with syntax versions
  higher than it supports. When absent, assumes the latest (currently 1).

  ### Schema Block

      schema Trading {
        id: 100
        version: 1
      }

  Optional. Present in master files. Declares the schema namespace
  (`id`) and version. Individual struct/enum files omit this block.

  ### Import

      import "order_created.grid"
      import "../events/order_side.grid"

  Imports definitions from another `.grid` file. Paths are resolved
  relative to the importing file's directory. Circular imports are
  detected and rejected. Duplicate imports across the tree are
  deduplicated (each file is parsed at most once).

  ### Struct

      struct Order (template_id: 1001) {
        id: uuid_string
        user_id: u64
        side: Side
        price: decimal(scale: 8), wire_format: i64
        quantity: u32, default: 0
        exchange: string8, presence: constant, value: "NYSE"
        notes?: string16

        group fills {
          price: u64
          qty: u32
        }

        batch commands {
          any_of: [PlaceOrder, CancelOrder]
          strategy: padded_union
        }
      }

      struct Trade (template_id: 1002, version: 2) {
        trade_id: uuid_string
        price: u64, since: 2
      }

  Attributes: `template_id` (required), `version` (optional, overrides
  schema-level version).

  ### Enum

      enum Side : u8 {
        buy = 1
        sell = 2
      }

  Backing type after `:` must be `u8`, `u16`, or `u32`.

  ### Composite Type

      type Price {
        mantissa: i64
        exponent: i8
      }

  ### Field Syntax

      name: type
      name: type(param: value)
      name: type, wire_format: i64, since: 2
      name?: type

  Trailing `?` marks the field as optional (`presence: :optional`).

  **Field options** (comma-separated after type):
    - `wire_format:` — override binary encoding type
    - `since:` — version the field was introduced
    - `default:` — default value
    - `presence:` — `:required`, `:optional`, or `:constant`
    - `value:` — constant value (with `presence: constant`)

  ### Built-in Types

  Fixed: `u8`, `u16`, `u32`, `u64`, `i8`, `i16`, `i32`, `i64`,
  `f32`, `f64`, `uuid`, `uuid_string`, `bool`, `timestamp_us`,
  `timestamp_ns`, `datetime_us`, `datetime_ns`, `decimal`,
  `positive_decimal`, `char_array`

  Variable: `string8`, `string16`, `string32`

  ### Type References

  Short names (e.g., `Side`, `OrderSide`) are resolved against enums,
  types, and structs declared or imported within the same schema's
  import tree. Each individual file should import the types it
  references for self-containment.

  ### Comments

      # Line comments start with #

  Comments extend to end of line. No block comment syntax.

  ## Formal Grammar (EBNF)

  The grammar below uses [Extended Backus-Naur Form](https://en.wikipedia.org/wiki/Extended_Backus%E2%80%93Naur_Form):
  `|` alternation, `[ ]` optional (zero or one), `{ }` repetition (zero or more),
  `( )` grouping. Terminal symbols are in `"quotes"`. Whitespace between
  tokens is implicit (the tokenizer splits on whitespace after stripping
  comments).

  ### Lexical Elements

      letter       = "A" … "Z" | "a" … "z"
      digit        = "0" … "9"
      ident        = ( letter | "_" ) { letter | digit | "_" }
      fieldIdent   = ident [ "?" ]
      intLit       = [ "-" ] digit { digit }
      strLit       = '"' { char } '"'
      comment      = "#" { any } newline

  Comments are stripped before tokenization and do not appear in the
  grammar productions below.

  ### Top-level

      gridFile     = [ syntaxDir ] { topLevelDef }
      topLevelDef  = importDecl
                   | schemaBlock
                   | structBlock
                   | enumBlock
                   | typeBlock

  ### Directives

      syntaxDir    = "@syntax" intLit

  Must be the first non-comment construct if present. The parser
  rejects values greater than `current_syntax()`.

  ### Import

      importDecl   = "import" strLit

  ### Schema

      schemaBlock  = "schema" [ ident ] "{" { schemaProp } "}"
      schemaProp   = ident ":" value

  Common properties: `id` (integer), `version` (integer). Properties are
  separated by whitespace; commas are not used.

  ### Struct

      structBlock  = "struct" ident "(" structAttrs ")" "{" { structMember } "}"
      structAttrs  = structAttr { "," structAttr }
      structAttr   = ident ":" value
      structMember = field | groupBlock | batchBlock

  Common attributes: `template_id` (required), `version` (optional).

  ### Enum

      enumBlock    = "enum" ident ":" ident "{" { enumValue } "}"
      enumValue    = ident "=" intLit

  The second `ident` is the backing type (`u8`, `u16`, or `u32`).

  ### Composite Type

      typeBlock    = "type" ident "{" { field } "}"

  ### Group

      groupBlock   = "group" ident "{" [groupProp] { field } "}"
                   | "group" ident ":" typeRef "{" [groupProp] "}"
      groupProp    = "framing" ":" "length_prefixed"

  ### Batch

      batchBlock   = "batch" ident "{" { batchProp } "}"
      batchProp    = "any_of" ":" "[" ident { "," ident } "]"
                   | "strategy" ":" ident

  ### Field

      field        = fieldIdent ":" typeExpr { "," fieldOption }
      typeExpr     = ident [ "(" typeParams ")" ]
      typeParams   = typeParam { "," typeParam }
      typeParam    = ident ":" value
      fieldOption  = "wire_format" ":" ident
                   | "since"       ":" intLit
                   | "default"     ":" value
                   | "presence"    ":" ( "required" | "optional" | "constant" )
                   | "value"       ":" value

  ### Value

      value        = intLit | strLit | ident

  When `value` matches an integer literal it is parsed as an integer.
  When it is a quoted string the quotes are stripped. Otherwise it is
  converted to an atom.
  """

  @current_syntax 1

  @doc "Returns the latest supported `.grid` syntax version."
  @spec current_syntax() :: pos_integer()
  def current_syntax, do: @current_syntax

  @default_max_identifiers 2_048
  @default_max_identifier_length 128

  defmodule Schema do
    @moduledoc "Parsed schema structure"
    defstruct syntax: nil,
              name: nil,
              id: nil,
              version: 1,
              types: %{},
              enums: %{},
              structs: %{},
              imports: []

    @type t :: %__MODULE__{
            syntax: pos_integer() | nil,
            name: atom() | nil,
            id: integer() | nil,
            version: integer(),
            types: map(),
            enums: map(),
            structs: map(),
            imports: [String.t()]
          }
  end

  defmodule StructDef do
    @moduledoc "Parsed struct definition"
    defstruct name: nil,
              template_id: nil,
              version: nil,
              fields: [],
              groups: [],
              batches: []
  end

  defmodule BatchDef do
    @moduledoc "Parsed batch definition"
    defstruct name: nil,
              any_of: [],
              strategy: :padded_union

    @type t :: %__MODULE__{
            name: atom() | nil,
            any_of: [atom()],
            strategy: atom()
          }
  end

  defmodule Field do
    @moduledoc "Parsed field structure"
    defstruct name: nil,
              type: nil,
              type_params: [],
              optional: false,
              wire_format: nil,
              since: nil,
              default: nil,
              presence: nil,
              value: nil,
              doc: nil

    @type t :: %__MODULE__{
            name: atom() | nil,
            type: atom() | nil,
            type_params: keyword(),
            optional: boolean(),
            wire_format: atom() | nil,
            since: integer() | nil,
            default: term(),
            presence: atom() | nil,
            value: term(),
            doc: String.t() | nil
          }
  end

  defmodule Group do
    @moduledoc "Parsed group structure"
    defstruct name: nil,
              fields: [],
              framing: nil,
              of_type: nil,
              doc: nil

    @type t :: %__MODULE__{
            name: atom() | nil,
            fields: [Field.t()],
            framing: :length_prefixed | nil,
            of_type: atom() | nil,
            doc: String.t() | nil
          }
  end

  defmodule TypeDef do
    @moduledoc """
    Parsed custom type definition.

    The `kind` discriminator determines which fields are populated:
    - `:composite` — field-based composite (existing `type` keyword), uses `fields`
    - `:prefixed_id` — PrefixedId type, uses `params` (prefix, tag)
    - `:char_array` — CharArray type, uses `params` (length)
    - `:bitset` — Bitset type, uses `underlying_type` and `values`
    """
    defstruct name: nil,
              kind: :composite,
              underlying_type: nil,
              params: %{},
              values: [],
              fields: []
  end

  defmodule EnumDef do
    @moduledoc "Parsed enum structure"
    defstruct name: nil,
              underlying_type: nil,
              values: []
  end

  @doc """
  Parses a `.grid` file and returns a Schema struct.

  ## Options

  - `:max_identifiers` - Maximum unique non-numeric identifiers allowed (default: #{@default_max_identifiers})
  - `:max_identifier_length` - Maximum identifier length in bytes (default: #{@default_max_identifier_length})
  """
  @spec parse_file(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse_file(path, opts \\ []) do
    case File.read(path) do
      {:ok, content} -> parse(content, opts)
      {:error, reason} -> {:error, {:file_error, path, reason}}
    end
  end

  @doc """
  Parses a `.grid` file, resolving any `import` directives recursively.

  Returns a single merged `Schema` with all definitions from imported files.
  Detects circular imports via a visited-path set.
  """
  @spec parse_file_with_imports(String.t(), keyword()) :: {:ok, Schema.t()} | {:error, term()}
  def parse_file_with_imports(path, opts \\ []) do
    resolve_with_imports(path, %{}, opts)
  end

  defp resolve_with_imports(path, visited, opts) do
    abs_path = Path.expand(path)

    if Map.has_key?(visited, abs_path) do
      {:error, {:circular_import, path}}
    else
      visited = Map.put(visited, abs_path, true)

      with {:ok, schema} <- parse_file(path, opts) do
        base_dir = Path.dirname(abs_path)
        resolve_imports(schema, base_dir, visited, opts)
      end
    end
  end

  defp resolve_imports(%Schema{imports: []} = schema, _base_dir, _visited, _opts) do
    {:ok, schema}
  end

  defp resolve_imports(%Schema{imports: imports} = schema, base_dir, visited, opts) do
    Enum.reduce_while(imports, {:ok, %{schema | imports: imports}}, fn import_path, {:ok, acc} ->
      full_path = Path.join(base_dir, import_path)

      case resolve_with_imports(full_path, visited, opts) do
        {:ok, imported} ->
          merged = merge_schemas(acc, imported)
          {:cont, {:ok, merged}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
  end

  defp merge_schemas(%Schema{} = base, %Schema{} = imported) do
    %{
      base
      | types: Map.merge(base.types, imported.types),
        enums: Map.merge(base.enums, imported.enums),
        structs: Map.merge(base.structs, imported.structs)
    }
  end

  @doc """
  Parses `.grid` content string and returns a Schema struct.

  ## Options

  - `:max_identifiers` - Maximum unique non-numeric identifiers allowed (default: #{@default_max_identifiers})
  - `:max_identifier_length` - Maximum identifier length in bytes (default: #{@default_max_identifier_length})
  """
  @spec parse(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse(content, opts \\ []) when is_binary(content) do
    tokens = tokenize(content)

    with :ok <- validate_identifier_safety(tokens, opts) do
      parse_tokens(tokens)
    end
  end

  # ============================================================================
  # Tokenizer
  # ============================================================================

  defp tokenize(content) do
    content
    |> String.replace(~r/#[^\n]*/, "")
    |> String.replace(~r/([\[\]\(\),\{\}])/, " \\1 ")
    |> then(&Regex.scan(~r/"(?:\\.|[^"])*"|[^\s]+/, &1))
    |> List.flatten()
    |> tokenize_stream([])
  end

  defp tokenize_stream([], acc), do: Enum.reverse(acc)

  defp tokenize_stream([token | rest], acc) do
    cond do
      token == "{" ->
        tokenize_stream(rest, [:lbrace | acc])

      token == "}" ->
        tokenize_stream(rest, [:rbrace | acc])

      token == "(" ->
        tokenize_stream(rest, [:lparen | acc])

      token == ")" ->
        tokenize_stream(rest, [:rparen | acc])

      token == ":" ->
        tokenize_stream(rest, [:colon | acc])

      token == "=" ->
        tokenize_stream(rest, [:equals | acc])

      token == "," ->
        tokenize_stream(rest, [:comma | acc])

      token == "[" ->
        tokenize_stream(rest, [:lbracket | acc])

      token == "]" ->
        tokenize_stream(rest, [:rbracket | acc])

      String.ends_with?(token, "]") ->
        word = String.trim_trailing(token, "]")

        if word == "" do
          tokenize_stream(rest, [:rbracket | acc])
        else
          tokenize_stream(rest, [:rbracket, {:word, word} | acc])
        end

      String.starts_with?(token, "[") ->
        word = String.trim_leading(token, "[")

        if word == "" do
          tokenize_stream(rest, [:lbracket | acc])
        else
          tokenize_stream(rest, [{:word, word}, :lbracket | acc])
        end

      String.ends_with?(token, "{") ->
        word = String.trim_trailing(token, "{")
        tokenize_stream(rest, [:lbrace, {:word, word} | acc])

      # Handle "(key:" or "(key" or "(1001)" - must come before ends_with?(":")
      String.starts_with?(token, "(") ->
        word = String.trim_leading(token, "(")

        cond do
          word == "" ->
            tokenize_stream(rest, [:lparen | acc])

          String.ends_with?(word, ")") ->
            # Handle "(1001)" -> :lparen, {:word, "1001"}, :rparen
            inner = String.trim_trailing(word, ")")
            tokenize_stream(rest, [:rparen, {:word, inner}, :lparen | acc])

          String.ends_with?(word, ":") ->
            # Handle "(template_id:" -> :lparen, {:word, "template_id"}, :colon
            key = String.trim_trailing(word, ":")
            tokenize_stream(rest, [:colon, {:word, key}, :lparen | acc])

          true ->
            tokenize_stream(rest, [{:word, word}, :lparen | acc])
        end

      String.ends_with?(token, ":") ->
        word = String.trim_trailing(token, ":")
        tokenize_stream(rest, [:colon, {:word, word} | acc])

      String.ends_with?(token, ",") ->
        word = String.trim_trailing(token, ",")
        tokenize_stream(rest, [:comma, {:word, word} | acc])

      String.ends_with?(token, ")") ->
        word = String.trim_trailing(token, ")")

        if word == "" do
          tokenize_stream(rest, [:rparen | acc])
        else
          tokenize_stream(rest, [:rparen, {:word, word} | acc])
        end

      String.starts_with?(token, "@") ->
        directive_name = String.trim_leading(token, "@")
        tokenize_stream(rest, [{:directive, directive_name} | acc])

      true ->
        tokenize_stream(rest, [{:word, token} | acc])
    end
  end

  defp validate_identifier_safety(tokens, opts) do
    max_identifiers = Keyword.get(opts, :max_identifiers, @default_max_identifiers)

    max_identifier_length =
      Keyword.get(opts, :max_identifier_length, @default_max_identifier_length)

    identifiers =
      tokens
      |> Enum.flat_map(fn
        {:word, word} when is_binary(word) -> [word]
        {:directive, _} -> []
        _ -> []
      end)
      |> Enum.reject(&looks_like_integer?/1)
      |> MapSet.new()
      |> MapSet.to_list()

    with :ok <- validate_identifier_lengths(identifiers, max_identifier_length),
         :ok <- validate_identifier_format(identifiers),
         :ok <- validate_identifier_budget(identifiers, max_identifiers) do
      :ok
    end
  end

  defp validate_identifier_lengths(identifiers, max_identifier_length) do
    case Enum.find(identifiers, fn word -> byte_size(word) > max_identifier_length end) do
      nil ->
        :ok

      word ->
        {:error, {:identifier_too_long, word, byte_size(word), max_identifier_length}}
    end
  end

  defp validate_identifier_format(identifiers) do
    case Enum.find(identifiers, fn word -> not valid_identifier?(word) end) do
      nil -> :ok
      word -> {:error, {:invalid_identifier, word}}
    end
  end

  defp validate_identifier_budget(identifiers, max_identifiers) do
    count = length(identifiers)

    if count > max_identifiers do
      {:error, {:too_many_identifiers, count, max_identifiers}}
    else
      :ok
    end
  end

  defp valid_identifier?(word) do
    String.starts_with?(word, "\"") or
      Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*\??$/, word)
  end

  defp looks_like_integer?(word) do
    case Integer.parse(word) do
      {_int, ""} -> true
      _ -> false
    end
  end

  # ============================================================================
  # Parser
  # ============================================================================

  defp parse_tokens(tokens) do
    case parse_top_level(tokens, %Schema{}) do
      {:ok, %Schema{syntax: nil} = schema} ->
        {:ok, %{schema | syntax: @current_syntax}}

      other ->
        other
    end
  end

  defp parse_top_level([], schema), do: {:ok, schema}

  defp parse_top_level([{:directive, "syntax"}, {:word, version_str} | rest], schema) do
    case Integer.parse(version_str) do
      {version, ""} when version > 0 and version <= @current_syntax ->
        parse_top_level(rest, %{schema | syntax: version})

      {version, ""} when version > @current_syntax ->
        {:error, {:unsupported_syntax, version, @current_syntax}}

      _ ->
        {:error, {:invalid_syntax_version, version_str}}
    end
  end

  defp parse_top_level([{:directive, name} | _], _schema) do
    {:error, {:unknown_directive, name}}
  end

  defp parse_top_level([{:word, "schema"} | rest], schema) do
    case parse_schema_block(rest) do
      {:ok, schema_meta, remaining} ->
        schema = %{
          schema
          | name: schema_meta[:name],
            id: schema_meta[:id],
            version: schema_meta[:version] || 1
        }

        parse_top_level(remaining, schema)

      {:error, _} = err ->
        err
    end
  end

  defp parse_top_level([{:word, "type"}, {:word, name} | rest], schema) do
    case parse_type_block(rest) do
      {:ok, fields, remaining} ->
        type = %TypeDef{name: String.to_atom(name), kind: :composite, fields: fields}
        schema = %{schema | types: Map.put(schema.types, type.name, type)}
        parse_top_level(remaining, schema)

      {:error, _} = err ->
        err
    end
  end

  defp parse_top_level([{:word, "prefixed_id"}, {:word, name} | rest], schema) do
    case parse_kv_type_block(rest) do
      {:ok, params, remaining} ->
        type = %TypeDef{name: String.to_atom(name), kind: :prefixed_id, params: params}
        schema = %{schema | types: Map.put(schema.types, type.name, type)}
        parse_top_level(remaining, schema)

      {:error, _} = err ->
        err
    end
  end

  defp parse_top_level([{:word, "char_array"}, {:word, name} | rest], schema) do
    case parse_kv_type_block(rest) do
      {:ok, params, remaining} ->
        type = %TypeDef{name: String.to_atom(name), kind: :char_array, params: params}
        schema = %{schema | types: Map.put(schema.types, type.name, type)}
        parse_top_level(remaining, schema)

      {:error, _} = err ->
        err
    end
  end

  defp parse_top_level(
         [{:word, "bitset"}, {:word, name}, :colon, {:word, underlying} | rest],
         schema
       ) do
    case parse_enum_block(rest) do
      {:ok, values, remaining} ->
        type = %TypeDef{
          name: String.to_atom(name),
          kind: :bitset,
          underlying_type: String.to_atom(underlying),
          values: values
        }

        schema = %{schema | types: Map.put(schema.types, type.name, type)}
        parse_top_level(remaining, schema)

      {:error, _} = err ->
        err
    end
  end

  defp parse_top_level(
         [{:word, "enum"}, {:word, name}, :colon, {:word, underlying} | rest],
         schema
       ) do
    case parse_enum_block(rest) do
      {:ok, values, remaining} ->
        enum = %EnumDef{
          name: String.to_atom(name),
          underlying_type: String.to_atom(underlying),
          values: values
        }

        schema = %{schema | enums: Map.put(schema.enums, enum.name, enum)}
        parse_top_level(remaining, schema)

      {:error, _} = err ->
        err
    end
  end

  # New syntax: struct Name (template_id: 1001) { ... }
  defp parse_top_level([{:word, "struct"}, {:word, name}, :lparen | rest], schema) do
    case parse_struct_attrs(rest) do
      {:ok, attrs, rest2} ->
        case parse_struct_block(rest2) do
          {:ok, fields, groups, batches, remaining} ->
            struct_def = %StructDef{
              name: String.to_atom(name),
              template_id: attrs[:template_id],
              version: attrs[:version],
              fields: fields,
              groups: groups,
              batches: batches
            }

            schema = %{schema | structs: Map.put(schema.structs, struct_def.name, struct_def)}
            parse_top_level(remaining, schema)

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  defp parse_top_level([{:word, "import"}, {:word, path_str} | rest], schema) do
    path = parse_value(path_str)

    if is_binary(path) do
      schema = %{schema | imports: schema.imports ++ [path]}
      parse_top_level(rest, schema)
    else
      {:error, {:invalid_import_path, path_str}}
    end
  end

  defp parse_top_level([token | _], _schema) do
    {:error, {:unexpected_token, token}}
  end

  # Parse struct attributes: template_id: 1001, version: 2
  defp parse_struct_attrs(tokens) do
    parse_struct_attrs(tokens, %{})
  end

  defp parse_struct_attrs([:rparen | rest], attrs) do
    {:ok, attrs, rest}
  end

  defp parse_struct_attrs([{:word, key}, :colon, {:word, value} | rest], attrs) do
    attrs = Map.put(attrs, String.to_atom(key), parse_value(value))
    parse_struct_attrs_continue(rest, attrs)
  end

  defp parse_struct_attrs([{:word, key}, {:word, value} | rest], attrs) do
    # Handle "key: value" where colon is attached to key (tokenized as "key:")
    attrs = Map.put(attrs, String.to_atom(key), parse_value(value))
    parse_struct_attrs_continue(rest, attrs)
  end

  defp parse_struct_attrs(tokens, _attrs) do
    {:error, {:invalid_struct_attrs, tokens}}
  end

  defp parse_struct_attrs_continue([:comma | rest], attrs) do
    parse_struct_attrs(rest, attrs)
  end

  defp parse_struct_attrs_continue([:rparen | rest], attrs) do
    {:ok, attrs, rest}
  end

  defp parse_struct_attrs_continue(tokens, _attrs) do
    {:error, {:invalid_struct_attrs, tokens}}
  end

  # Parse schema { name: value ... }
  defp parse_schema_block([{:word, name}, :lbrace | rest]) do
    parse_kv_block(rest, %{name: String.to_atom(name)})
  end

  defp parse_schema_block([:lbrace | rest]) do
    parse_kv_block(rest, %{})
  end

  defp parse_schema_block(tokens) do
    {:error, {:expected_brace, tokens}}
  end

  defp parse_kv_block([:rbrace | rest], acc), do: {:ok, acc, rest}

  defp parse_kv_block([{:word, key}, :colon, {:word, value} | rest], acc) do
    parsed_value = parse_value(value)
    parse_kv_block(rest, Map.put(acc, String.to_atom(key), parsed_value))
  end

  defp parse_kv_block([{:word, key}, {:word, value} | rest], acc) do
    # Handle "key: value" tokenized as two words when colon attached to key
    parsed_value = parse_value(value)
    parse_kv_block(rest, Map.put(acc, String.to_atom(key), parsed_value))
  end

  defp parse_kv_block(tokens, _acc) do
    {:error, {:invalid_kv_block, tokens}}
  end

  defp parse_kv_type_block([:lbrace | rest]), do: parse_kv_block(rest, %{})
  defp parse_kv_type_block(tokens), do: {:error, {:expected_brace, tokens}}

  # Parse type { field: type ... }
  defp parse_type_block([:lbrace | rest]) do
    parse_fields_block(rest, [])
  end

  defp parse_type_block(tokens) do
    {:error, {:expected_brace, tokens}}
  end

  # Parse enum { name = value ... }
  defp parse_enum_block([:lbrace | rest]) do
    parse_enum_values(rest, [])
  end

  defp parse_enum_block(tokens) do
    {:error, {:expected_brace, tokens}}
  end

  defp parse_enum_values([:rbrace | rest], acc) do
    {:ok, Enum.reverse(acc), rest}
  end

  defp parse_enum_values(
         [
           {:word, name},
           :equals,
           {:word, value},
           :comma,
           {:word, "doc"},
           :colon,
           {:word, doc} | rest
         ],
         acc
       ) do
    parse_enum_values(rest, [{String.to_atom(name), parse_value(value), parse_value(doc)} | acc])
  end

  defp parse_enum_values([{:word, name}, :equals, {:word, value} | rest], acc) do
    parse_enum_values(rest, [{String.to_atom(name), parse_value(value)} | acc])
  end

  defp parse_enum_values(
         [{:word, name}, {:word, value}, :comma, {:word, "doc"}, :colon, {:word, doc} | rest],
         acc
       ) do
    case Integer.parse(value) do
      {int, ""} ->
        parse_enum_values(rest, [{String.to_atom(name), int, parse_value(doc)} | acc])

      _ ->
        {:error, {:invalid_enum_value, name, value}}
    end
  end

  defp parse_enum_values([{:word, name}, {:word, value} | rest], acc) do
    # Handle "name = value" where = might be attached
    case Integer.parse(value) do
      {int, ""} ->
        parse_enum_values(rest, [{String.to_atom(name), int} | acc])

      _ ->
        {:error, {:invalid_enum_value, name, value}}
    end
  end

  defp parse_enum_values(tokens, _acc) do
    {:error, {:invalid_enum_block, tokens}}
  end

  # Parse struct { fields... groups... batches... }
  defp parse_struct_block([:lbrace | rest]) do
    parse_struct_body(rest, [], [], [])
  end

  defp parse_struct_block(tokens) do
    {:error, {:expected_brace, tokens}}
  end

  defp parse_struct_body([:rbrace | rest], fields, groups, batches) do
    {:ok, Enum.reverse(fields), Enum.reverse(groups), Enum.reverse(batches), rest}
  end

  defp parse_struct_body(
         [{:word, "group"}, {:word, name}, :colon, {:word, scalar_type}, :lbrace | rest],
         fields,
         groups,
         batches
       ) do
    {group_attrs, rest2} = extract_group_attrs(rest)

    case rest2 do
      [:rbrace | remaining] ->
        group = %Group{
          name: String.to_atom(name),
          of_type: String.to_atom(scalar_type),
          framing: group_attrs.framing,
          doc: group_attrs.doc
        }

        parse_struct_body(remaining, fields, [group | groups], batches)

      _ ->
        {:error, {:expected_closing_brace_for_scalar_group, name}}
    end
  end

  defp parse_struct_body(
         [{:word, "group"}, {:word, name}, :lbrace | rest],
         fields,
         groups,
         batches
       ) do
    case parse_group_block(rest) do
      {:ok, group, remaining} ->
        group = %{group | name: String.to_atom(name)}
        parse_struct_body(remaining, fields, [group | groups], batches)

      {:error, _} = err ->
        err
    end
  end

  defp parse_struct_body([{:word, "group"}, {:word, name} | rest], fields, groups, batches) do
    case rest do
      [:colon, {:word, scalar_type}, :lbrace | rest2] ->
        {group_attrs, rest3} = extract_group_attrs(rest2)

        case rest3 do
          [:rbrace | remaining] ->
            group = %Group{
              name: String.to_atom(name),
              of_type: String.to_atom(scalar_type),
              framing: group_attrs.framing,
              doc: group_attrs.doc
            }

            parse_struct_body(remaining, fields, [group | groups], batches)

          _ ->
            {:error, {:expected_closing_brace_for_scalar_group, name}}
        end

      [:lbrace | rest2] ->
        case parse_group_block(rest2) do
          {:ok, group, remaining} ->
            group = %{group | name: String.to_atom(name)}
            parse_struct_body(remaining, fields, [group | groups], batches)

          {:error, _} = err ->
            err
        end

      _ ->
        {:error, {:expected_brace_after_group, name}}
    end
  end

  defp parse_struct_body(
         [{:word, "batch"}, {:word, name}, :lbrace | rest],
         fields,
         groups,
         batches
       ) do
    case parse_batch_block(rest) do
      {:ok, %BatchDef{} = batch_def, remaining} ->
        batch = %BatchDef{batch_def | name: String.to_atom(name)}
        parse_struct_body(remaining, fields, groups, [batch | batches])

      {:error, _} = err ->
        err
    end
  end

  defp parse_struct_body([{:word, "batch"}, {:word, name} | rest], fields, groups, batches) do
    case rest do
      [:lbrace | rest2] ->
        case parse_batch_block(rest2) do
          {:ok, %BatchDef{} = batch_def, remaining} ->
            batch = %BatchDef{batch_def | name: String.to_atom(name)}
            parse_struct_body(remaining, fields, groups, [batch | batches])

          {:error, _} = err ->
            err
        end

      _ ->
        {:error, {:expected_brace_after_batch, name}}
    end
  end

  defp parse_struct_body([{:word, name}, :colon, {:word, type} | rest], fields, groups, batches) do
    {field_name, optional} = parse_field_name(name)

    case parse_field_with_extras(type, rest) do
      {:ok, field, remaining} ->
        field = %{field | name: field_name, optional: optional}
        parse_struct_body(remaining, [field | fields], groups, batches)

      {:error, _} = err ->
        err
    end
  end

  defp parse_struct_body([{:word, name}, {:word, type} | rest], fields, groups, batches) do
    {field_name, optional} = parse_field_name(name)

    case parse_field_with_extras(type, rest) do
      {:ok, field, remaining} ->
        field = %{field | name: field_name, optional: optional}
        parse_struct_body(remaining, [field | fields], groups, batches)

      {:error, _} = err ->
        err
    end
  end

  defp parse_struct_body(tokens, _fields, _groups, _batches) do
    {:error, {:invalid_struct_body, tokens}}
  end

  # Parse batch body: any_of: [Type1, Type2], strategy: padded_union
  defp parse_batch_block(tokens) do
    parse_batch_attrs(tokens, %BatchDef{})
  end

  defp parse_batch_attrs([:rbrace | rest], batch) do
    {:ok, batch, rest}
  end

  defp parse_batch_attrs([{:word, "any_of"}, :colon, :lbracket | rest], batch) do
    case parse_list(rest, []) do
      {:ok, [], _remaining} ->
        {:error, {:empty_any_of}}

      {:ok, items, remaining} ->
        parse_batch_attrs(remaining, %{batch | any_of: Enum.map(items, &String.to_atom/1)})

      {:error, _} = err ->
        err
    end
  end

  defp parse_batch_attrs([{:word, "any_of"}, :lbracket | rest], batch) do
    case parse_list(rest, []) do
      {:ok, [], _remaining} ->
        {:error, {:empty_any_of}}

      {:ok, items, remaining} ->
        parse_batch_attrs(remaining, %{batch | any_of: Enum.map(items, &String.to_atom/1)})

      {:error, _} = err ->
        err
    end
  end

  defp parse_batch_attrs([{:word, "strategy"}, :colon, {:word, val} | rest], batch) do
    parse_batch_attrs(rest, %{batch | strategy: String.to_atom(val)})
  end

  defp parse_batch_attrs([{:word, "strategy"}, {:word, val} | rest], batch) do
    parse_batch_attrs(rest, %{batch | strategy: String.to_atom(val)})
  end

  defp parse_batch_attrs(tokens, _batch) do
    {:error, {:invalid_batch_block, tokens}}
  end

  defp parse_list([:rbracket | rest], acc), do: {:ok, Enum.reverse(acc), rest}

  defp parse_list([{:word, item}, :comma | rest], acc) do
    parse_list(rest, [item | acc])
  end

  defp parse_list([{:word, item} | rest], acc) do
    parse_list(rest, [item | acc])
  end

  defp parse_list(tokens, _acc), do: {:error, {:invalid_list, tokens}}

  # Parse group block: extract optional properties (framing) then delegate to parse_fields_block
  defp parse_group_block(tokens) do
    {group_attrs, rest} = extract_group_attrs(tokens)

    case parse_fields_block(rest, []) do
      {:ok, group_fields, remaining} ->
        {:ok, %Group{fields: group_fields, framing: group_attrs.framing, doc: group_attrs.doc},
         remaining}

      {:error, _} = err ->
        err
    end
  end

  defp extract_group_attrs(tokens), do: parse_group_attrs(tokens, %{framing: nil, doc: nil})

  defp parse_group_attrs([{:word, "framing"}, :colon, {:word, "length_prefixed"} | rest], attrs) do
    parse_group_attrs(rest, %{attrs | framing: :length_prefixed})
  end

  defp parse_group_attrs([{:word, "doc"}, :colon, {:word, doc} | rest], attrs) do
    parse_group_attrs(rest, %{attrs | doc: parse_value(doc)})
  end

  defp parse_group_attrs(tokens, attrs), do: {attrs, tokens}

  # Parse fields block for types and groups
  defp parse_fields_block([:rbrace | rest], acc) do
    {:ok, Enum.reverse(acc), rest}
  end

  defp parse_fields_block([{:word, name}, :colon, {:word, type} | rest], acc) do
    {field_name, optional} = parse_field_name(name)

    case parse_field_with_extras(type, rest) do
      {:ok, field, remaining} ->
        field = %{field | name: field_name, optional: optional}
        parse_fields_block(remaining, [field | acc])

      {:error, _} = err ->
        err
    end
  end

  defp parse_fields_block([{:word, name}, {:word, type} | rest], acc) do
    {field_name, optional} = parse_field_name(name)

    case parse_field_with_extras(type, rest) do
      {:ok, field, remaining} ->
        field = %{field | name: field_name, optional: optional}
        parse_fields_block(remaining, [field | acc])

      {:error, _} = err ->
        err
    end
  end

  defp parse_fields_block(tokens, _acc) do
    {:error, {:invalid_fields_block, tokens}}
  end

  # Helper to parse field name and optional marker
  defp parse_field_name(name) do
    if String.ends_with?(name, "?") do
      {String.to_atom(String.trim_trailing(name, "?")), true}
    else
      {String.to_atom(name), false}
    end
  end

  # ============================================================================
  # Field extras: parameterized types and field options
  # ============================================================================

  @known_field_opts ~w(wire_format since default presence value doc)a

  defp parse_field_with_extras(type_word, rest) do
    type = String.to_atom(type_word)

    case maybe_parse_type_params(rest) do
      {:ok, type_params, rest2} ->
        {field_opts, rest3} = maybe_parse_field_opts(rest2)
        opts = Map.new(field_opts)

        field = %Field{
          type: type,
          type_params: type_params,
          wire_format: opts[:wire_format],
          since: opts[:since],
          default: opts[:default],
          presence: opts[:presence],
          value: opts[:value],
          doc: opts[:doc]
        }

        {:ok, field, rest3}

      {:error, _} = err ->
        err
    end
  end

  defp maybe_parse_type_params([:lparen | rest]), do: parse_type_params(rest, [])
  defp maybe_parse_type_params(tokens), do: {:ok, [], tokens}

  defp parse_type_params([:rparen | rest], acc), do: {:ok, Enum.reverse(acc), rest}

  defp parse_type_params([{:word, key}, :colon, {:word, val} | rest], acc) do
    parse_type_params_continue(rest, [{String.to_atom(key), parse_value(val)} | acc])
  end

  defp parse_type_params(tokens, _acc), do: {:error, {:invalid_type_params, tokens}}

  defp parse_type_params_continue([:comma | rest], acc), do: parse_type_params(rest, acc)
  defp parse_type_params_continue([:rparen | rest], acc), do: {:ok, Enum.reverse(acc), rest}
  defp parse_type_params_continue(tokens, _acc), do: {:error, {:invalid_type_params, tokens}}

  defp maybe_parse_field_opts([:comma, {:word, key}, :colon, {:word, val} | rest]) do
    key_atom = String.to_atom(key)

    if key_atom in @known_field_opts do
      parse_field_opts(rest, [{key_atom, parse_value(val)}])
    else
      {[], [:comma, {:word, key}, :colon, {:word, val} | rest]}
    end
  end

  defp maybe_parse_field_opts(tokens), do: {[], tokens}

  defp parse_field_opts([:comma, {:word, key}, :colon, {:word, val} | rest], acc) do
    key_atom = String.to_atom(key)

    if key_atom in @known_field_opts do
      parse_field_opts(rest, [{key_atom, parse_value(val)} | acc])
    else
      {Enum.reverse(acc), [:comma, {:word, key}, :colon, {:word, val} | rest]}
    end
  end

  defp parse_field_opts(tokens, acc), do: {Enum.reverse(acc), tokens}

  # Helper to parse values (integers, atoms, quoted strings)
  defp parse_value(value) when is_binary(value) do
    if byte_size(value) >= 2 and String.starts_with?(value, "\"") and
         String.ends_with?(value, "\"") do
      String.slice(value, 1..-2//1)
    else
      case Integer.parse(value) do
        {int, ""} -> int
        _ -> String.to_atom(value)
      end
    end
  end
end
