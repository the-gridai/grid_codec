defmodule GridCodec.Schema.Parser do
  @moduledoc """
  Parser for `.grid` schema files.

  ## Syntax

      # Comments start with #
      
      schema Trading {
        id: 100
        version: 1
      }
      
      type Price {
        mantissa: i64
        exponent: i8
      }
      
      enum Side : u8 {
        buy = 1
        sell = 2
      }
      
      struct Order (template_id: 1001) {
        id: uuid_string
        user_id: u64
        side: Side
        price: Price
        quantity: u32
        
        group fills {
          price: u64
          qty: u32
        }
      }
      
      # Override version for specific struct
      struct Trade (template_id: 1002, version: 2) {
        trade_id: uuid_string
        price: u64
      }
  """

  @default_max_identifiers 2_048
  @default_max_identifier_length 128

  defmodule Schema do
    @moduledoc "Parsed schema structure"
    defstruct name: nil,
              id: nil,
              version: 1,
              types: %{},
              enums: %{},
              structs: %{}

    @type t :: %__MODULE__{
            name: atom() | nil,
            id: integer() | nil,
            version: integer(),
            types: map(),
            enums: map(),
            structs: map()
          }
  end

  defmodule StructDef do
    @moduledoc "Parsed struct definition"
    defstruct name: nil,
              template_id: nil,
              version: nil,
              fields: [],
              groups: []
  end

  defmodule Field do
    @moduledoc "Parsed field structure"
    defstruct name: nil,
              type: nil,
              optional: false
  end

  defmodule Group do
    @moduledoc "Parsed group structure"
    defstruct name: nil,
              fields: []
  end

  defmodule CompositeType do
    @moduledoc "Parsed composite type structure"
    defstruct name: nil,
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
    # Remove comments
    |> String.replace(~r/#[^\n]*/, "")
    |> String.split(~r/\s+/, trim: true)
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
    Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_?]*$/, word)
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
    parse_top_level(tokens, %Schema{})
  end

  defp parse_top_level([], schema), do: {:ok, schema}

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
        type = %CompositeType{name: String.to_atom(name), fields: fields}
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
          {:ok, fields, groups, remaining} ->
            struct_def = %StructDef{
              name: String.to_atom(name),
              template_id: attrs[:template_id],
              version: attrs[:version],
              fields: fields,
              groups: groups
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

  # Legacy syntax: message Name (1001) { ... } - for backwards compatibility
  defp parse_top_level(
         [{:word, "message"}, {:word, name}, :lparen, {:word, tid_str}, :rparen | rest],
         schema
       ) do
    case Integer.parse(tid_str) do
      {tid, ""} ->
        case parse_struct_block(rest) do
          {:ok, fields, groups, remaining} ->
            struct_def = %StructDef{
              name: String.to_atom(name),
              template_id: tid,
              version: nil,
              fields: fields,
              groups: groups
            }

            schema = %{schema | structs: Map.put(schema.structs, struct_def.name, struct_def)}
            parse_top_level(remaining, schema)

          {:error, _} = err ->
            err
        end

      _ ->
        {:error, {:invalid_template_id, tid_str}}
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

  defp parse_struct_attrs_continue([{:word, _} = next | rest], attrs) do
    # Next attribute without comma
    parse_struct_attrs([next | rest], attrs)
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

  defp parse_enum_values([{:word, name}, :equals, {:word, value} | rest], acc) do
    parse_enum_values(rest, [{String.to_atom(name), parse_value(value)} | acc])
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

  # Parse struct { fields... groups... }
  defp parse_struct_block([:lbrace | rest]) do
    parse_struct_body(rest, [], [])
  end

  defp parse_struct_block(tokens) do
    {:error, {:expected_brace, tokens}}
  end

  defp parse_struct_body([:rbrace | rest], fields, groups) do
    {:ok, Enum.reverse(fields), Enum.reverse(groups), rest}
  end

  defp parse_struct_body([{:word, "group"}, {:word, name}, :lbrace | rest], fields, groups) do
    case parse_fields_block(rest, []) do
      {:ok, group_fields, remaining} ->
        group = %Group{name: String.to_atom(name), fields: group_fields}
        parse_struct_body(remaining, fields, [group | groups])

      {:error, _} = err ->
        err
    end
  end

  defp parse_struct_body([{:word, "group"}, {:word, name} | rest], fields, groups) do
    # Handle "group name {" where { is separate
    case rest do
      [:lbrace | rest2] ->
        case parse_fields_block(rest2, []) do
          {:ok, group_fields, remaining} ->
            group = %Group{name: String.to_atom(name), fields: group_fields}
            parse_struct_body(remaining, fields, [group | groups])

          {:error, _} = err ->
            err
        end

      _ ->
        {:error, {:expected_brace_after_group, name}}
    end
  end

  defp parse_struct_body([{:word, name}, :colon, {:word, type} | rest], fields, groups) do
    {field_name, optional} = parse_field_name(name)
    field = %Field{name: field_name, type: String.to_atom(type), optional: optional}
    parse_struct_body(rest, [field | fields], groups)
  end

  defp parse_struct_body([{:word, name}, {:word, type} | rest], fields, groups) do
    # Handle "name: type" where colon attached to name
    {field_name, optional} = parse_field_name(name)
    field = %Field{name: field_name, type: String.to_atom(type), optional: optional}
    parse_struct_body(rest, [field | fields], groups)
  end

  defp parse_struct_body(tokens, _fields, _groups) do
    {:error, {:invalid_struct_body, tokens}}
  end

  # Parse fields block for types and groups
  defp parse_fields_block([:rbrace | rest], acc) do
    {:ok, Enum.reverse(acc), rest}
  end

  defp parse_fields_block([{:word, name}, :colon, {:word, type} | rest], acc) do
    {field_name, optional} = parse_field_name(name)
    field = %Field{name: field_name, type: String.to_atom(type), optional: optional}
    parse_fields_block(rest, [field | acc])
  end

  defp parse_fields_block([{:word, name}, {:word, type} | rest], acc) do
    {field_name, optional} = parse_field_name(name)
    field = %Field{name: field_name, type: String.to_atom(type), optional: optional}
    parse_fields_block(rest, [field | acc])
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

  # Helper to parse values (integers, atoms, strings)
  defp parse_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> String.to_atom(value)
    end
  end

  # ============================================================================
  # Backwards Compatibility - expose .messages as alias for .structs
  # ============================================================================

  @doc """
  Returns structs map (for backwards compatibility, also aliased as messages).
  """
  def messages(%Schema{structs: structs}), do: structs
end
