defmodule GridCodec.Header do
  @moduledoc """
  Message header for GridCodec binary format.

  GridCodec uses a compact header structure that provides:
  - Message identification (schema_id, template_id)
  - Version tracking for schema evolution
  - Block length for safe parsing

  ## Wire Format

      ┌─────────────────────────────────────────────────────────┐
      │ Header (8 bytes)                                        │
      │ ┌────────────┬─────────────┬───────────┬─────────────┐ │
      │ │ Block Len  │ Template ID │ Schema ID │ Version     │ │
      │ │ (u16 LE)   │ (u16 LE)    │ (u16 LE)  │ (u16 LE)    │ │
      │ └────────────┴─────────────┴───────────┴─────────────┘ │
      └─────────────────────────────────────────────────────────┘

  ## Fields

  - **block_length**: Size of the fixed-field block in bytes
  - **template_id**: Identifies the message type within a schema
  - **schema_id**: Identifies the schema/application
  - **version**: Schema version for evolution

  ## Usage

      # Encode header
      header = GridCodec.Header.encode(block_length: 64, template_id: 1, schema_id: 100, version: 1)

      # Decode header
      {:ok, info, rest} = GridCodec.Header.decode(binary)
      # info = %{block_length: 64, template_id: 1, schema_id: 100, version: 1}

  ## Schema Evolution

  The version field enables safe rolling deploys:
  - New fields can be added at the end of the fixed block
  - Old readers skip unknown fields using block_length
  - Use `since: version` in field definitions for documentation
  """

  @header_size 8

  @type header_info :: %{
          block_length: non_neg_integer(),
          template_id: non_neg_integer(),
          schema_id: non_neg_integer(),
          version: non_neg_integer()
        }

  @type t :: header_info()

  @doc """
  Returns the header size in bytes.
  """
  @spec size() :: pos_integer()
  def size, do: @header_size

  @doc """
  Encodes a message header.

  ## Options

  - `:block_length` - Size of fixed-field block (required)
  - `:template_id` - Message type identifier (required)
  - `:schema_id` - Schema identifier (default: 0)
  - `:version` - Schema version (default: 1)

  ## Example

      iex> GridCodec.Header.encode(block_length: 32, template_id: 1)
      <<32, 0, 1, 0, 0, 0, 1, 0>>
  """
  @spec encode(keyword()) :: binary()
  def encode(opts) do
    block_length = Keyword.fetch!(opts, :block_length)
    template_id = Keyword.fetch!(opts, :template_id)
    schema_id = Keyword.get(opts, :schema_id, 0)
    version = Keyword.get(opts, :version, 1)

    <<
      block_length::little-16,
      template_id::little-16,
      schema_id::little-16,
      version::little-16
    >>
  end

  @doc """
  Decodes a message header from binary.

  Returns `{:ok, header_info, rest}` or `{:error, reason}`.

  ## Example

      iex> {:ok, info, rest} = GridCodec.Header.decode(<<32, 0, 1, 0, 0, 0, 1, 0, "payload">>)
      iex> info
      %{block_length: 32, template_id: 1, schema_id: 0, version: 1}
      iex> rest
      "payload"
  """
  @spec decode(binary()) :: {:ok, header_info(), binary()} | {:error, term()}
  def decode(<<
        block_length::little-16,
        template_id::little-16,
        schema_id::little-16,
        version::little-16,
        rest::binary
      >>) do
    info = %{
      block_length: block_length,
      template_id: template_id,
      schema_id: schema_id,
      version: version
    }

    {:ok, info, rest}
  end

  def decode(binary) when byte_size(binary) < @header_size do
    {:error, {:insufficient_data, byte_size(binary), @header_size}}
  end

  @doc """
  Decodes a message header, raising on error.
  """
  @spec decode!(binary()) :: {header_info(), binary()}
  def decode!(binary) do
    case decode(binary) do
      {:ok, info, rest} -> {info, rest}
      {:error, reason} -> raise ArgumentError, "Invalid header: #{inspect(reason)}"
    end
  end

  @doc """
  Extracts just the template_id from a binary without full decode.

  Useful for routing/dispatching without parsing the entire message.
  """
  @spec template_id(binary()) :: {:ok, non_neg_integer()} | {:error, term()}
  def template_id(<<_block_len::16, template_id::little-16, _rest::binary>>) do
    {:ok, template_id}
  end

  def template_id(binary) when byte_size(binary) < 4 do
    {:error, :insufficient_data}
  end

  @doc """
  Validates a header without consuming the binary.

  Checks that block_length is reasonable and version is supported.
  """
  @spec validate(binary(), keyword()) :: :ok | {:error, term()}
  def validate(binary, opts \\ []) do
    max_block_length = Keyword.get(opts, :max_block_length, 65_535)
    max_version = Keyword.get(opts, :max_version, 65_535)

    case decode(binary) do
      {:ok, %{block_length: bl}, _} when bl > max_block_length ->
        {:error, {:block_length_exceeded, bl, max_block_length}}

      {:ok, %{version: v}, _} when v > max_version ->
        {:error, {:version_exceeded, v, max_version}}

      {:ok, _, _} ->
        :ok

      {:error, _} = error ->
        error
    end
  end
end
