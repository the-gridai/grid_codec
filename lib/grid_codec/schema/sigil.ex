defmodule GridCodec.Schema.Sigil do
  @moduledoc """
  Sigil for parsing `.grid` schema syntax inline.

  ## Usage

      import GridCodec.Schema.Sigil

      schema = ~g\"\"\"
      schema Trading {
        id: 100
        version: 1
      }

      message Order (1001) {
        id: uuid_string
        user_id: u64
      }
      \"\"\"

      schema.messages[:Order].template_id  # => 1001

  ## In Module Definition

      defmodule MyApp.Order do
        use GridCodec.Struct,
          grid_schema: ~g\"\"\"
            schema { id: 100 }
            message Order (1001) {
              id: uuid_string
              quantity: u32
            }
          \"\"\",
          message: :Order
      end

  ## Modifiers

  - `~g` - Returns parsed schema struct (runtime parsing)
  - `~G` - Same as `~g`, but no interpolation allowed
  """

  @doc """
  Parses grid schema syntax at runtime.

  Returns a `GridCodec.Schema.Parser.Schema` struct.
  """
  defmacro sigil_g(term, modifiers)

  defmacro sigil_g({:<<>>, _meta, [string]}, []) when is_binary(string) do
    case GridCodec.Schema.Parser.parse(string) do
      {:ok, schema} ->
        Macro.escape(schema)

      {:error, reason} ->
        raise ArgumentError, "Invalid grid schema: #{inspect(reason)}"
    end
  end

  defmacro sigil_g({:<<>>, _, _} = term, []) do
    quote do
      case GridCodec.Schema.Parser.parse(unquote(term)) do
        {:ok, schema} -> schema
        {:error, reason} -> raise ArgumentError, "Invalid grid schema: #{inspect(reason)}"
      end
    end
  end

  @doc """
  Parses grid schema syntax at compile time (no interpolation).

  Returns a `GridCodec.Schema.Parser.Schema` struct.
  """
  defmacro sigil_G({:<<>>, _meta, [string]}, []) when is_binary(string) do
    case GridCodec.Schema.Parser.parse(string) do
      {:ok, schema} ->
        Macro.escape(schema)

      {:error, reason} ->
        raise ArgumentError, "Invalid grid schema: #{inspect(reason)}"
    end
  end
end
