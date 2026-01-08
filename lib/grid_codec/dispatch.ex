defmodule GridCodec.Dispatch do
  @moduledoc """
  Compile-time message dispatch for framed GridCodec messages.

  This module provides a macro to define a dispatch table that routes
  incoming framed messages to the correct decoder based on their header.

  ## Overview

  When messages are encoded with `encode!/1`, they include an 8-byte header
  containing `{schema_id, template_id}`. The dispatch table uses these to
  route to the correct codec at runtime.

  ## Usage

  Define a dispatch module in your application:

      defmodule MyApp.Events.Dispatch do
        use GridCodec.Dispatch

        codecs [
          MyApp.Events.OrderCreated,   # template_id: 1
          MyApp.Events.OrderFilled,    # template_id: 2
          MyApp.Events.OrderCancelled  # template_id: 3
        ]
      end

  Then use it to decode incoming messages:

      {:ok, data, codec} = MyApp.Events.Dispatch.decode(framed_binary)
      # codec is the module that decoded the message

  ## Compile-Time Validation

  The `codecs/1` macro validates at compile time that:
  - All modules implement the GridCodec callbacks
  - No two codecs have the same `{schema_id, template_id}` pair

  If conflicts are detected, compilation fails with a clear error message.

  ## Wire Format

  Framed messages have this structure:

      ┌─────────────────────────────────────────────────────────┐
      │ Header (8 bytes)                                        │
      │ ┌────────────┬─────────────┬───────────┬─────────────┐ │
      │ │ Block Len  │ Template ID │ Schema ID │ Version     │ │
      │ │ (u16 LE)   │ (u16 LE)    │ (u16 LE)  │ (u16 LE)    │ │
      │ └────────────┴─────────────┴───────────┴─────────────┘ │
      ├─────────────────────────────────────────────────────────┤
      │ Payload                                                 │
      └─────────────────────────────────────────────────────────┘

  ## Rolling Upgrades

  Since the dispatch table is compiled into your release:
  - Each release has a deterministic dispatch table
  - New codecs require a new release
  - Old nodes gracefully handle unknown messages with `{:error, :unknown_message}`

  ## Example

      # Define codecs
      defmodule MyApp.Events.OrderCreated do
        use GridCodec.Struct, template_id: 1, schema_id: 100

        defcodec do
          field :order_id, :uuid
          field :price, :u64
        end
      end

      defmodule MyApp.Events.OrderFilled do
        use GridCodec.Struct, template_id: 2, schema_id: 100

        defcodec do
          field :order_id, :uuid
          field :fill_price, :u64
        end
      end

      # Define dispatch
      defmodule MyApp.Events.Dispatch do
        use GridCodec.Dispatch

        codecs [
          MyApp.Events.OrderCreated,
          MyApp.Events.OrderFilled
        ]
      end

      # Encode (struct required)
      order = %MyApp.Events.OrderCreated{order_id: <<1::128>>, price: 100}
      binary = MyApp.Events.OrderCreated.encode!(order)

      # Dispatch decode
      {:ok, data, MyApp.Events.OrderCreated} = MyApp.Events.Dispatch.decode(binary)
  """

  @doc """
  Sets up a dispatch module.

  Use this in your module and then call `codecs/1` to register codecs.

  ## Example

      defmodule MyApp.Dispatch do
        use GridCodec.Dispatch

        codecs [MyApp.Events.OrderCreated, MyApp.Events.OrderFilled]
      end
  """
  defmacro __using__(_opts) do
    quote do
      import GridCodec.Dispatch, only: [codecs: 1]
    end
  end

  @doc """
  Registers codecs and generates the dispatch table.

  This macro:
  1. Validates all codecs implement required callbacks
  2. Checks for `{schema_id, template_id}` conflicts
  3. Generates a compile-time lookup table
  4. Defines `decode/1`, `decode!/1`, `wrap/1`, `lookup/2`, and `list_codecs/0`

  ## Compile-Time Errors

  Raises `CompileError` if:
  - A codec doesn't export `__template_id__/0`, `__schema_id__/0`, `__version__/0`
  - Two codecs have the same `{schema_id, template_id}`

  ## Example

      codecs [
        MyApp.Events.OrderCreated,
        MyApp.Events.OrderFilled
      ]
  """
  defmacro codecs(codec_modules) do
    quote bind_quoted: [codec_modules: codec_modules] do
      # Validate and build dispatch table at compile time
      dispatch_table =
        codec_modules
        |> Enum.map(fn module ->
          # Validate module exports required functions
          unless function_exported?(module, :__template_id__, 0) do
            raise CompileError,
              description:
                "#{inspect(module)} does not export __template_id__/0. " <>
                  "Did you forget to use GridCodec with template_id option?"
          end

          unless function_exported?(module, :__schema_id__, 0) do
            raise CompileError,
              description:
                "#{inspect(module)} does not export __schema_id__/0. " <>
                  "Did you forget to use GridCodec with schema_id option?"
          end

          unless function_exported?(module, :__version__, 0) do
            raise CompileError,
              description: "#{inspect(module)} does not export __version__/0."
          end

          template_id = module.__template_id__()
          schema_id = module.__schema_id__()
          version = module.__version__()

          {{schema_id, template_id}, %{module: module, version: version}}
        end)
        |> Enum.reduce(%{}, fn {{schema_id, template_id} = key, info}, acc ->
          if Map.has_key?(acc, key) do
            existing = Map.get(acc, key)

            raise CompileError,
              description:
                "Conflicting template_id! " <>
                  "#{inspect(info.module)} and #{inspect(existing.module)} " <>
                  "both have {schema_id: #{schema_id}, template_id: #{template_id}}. " <>
                  "Each codec must have a unique {schema_id, template_id} pair."
          end

          Map.put(acc, key, info)
        end)

      @dispatch_table dispatch_table
      @codec_modules codec_modules

      @doc """
      Decodes a framed binary message, routing to the correct codec.

      ## Returns

      - `{:ok, decoded_data, codec_module}` on success
      - `{:error, :unknown_message}` if no codec is registered for this message type
      - `{:error, {:version_too_new, got, max}}` if message version exceeds codec
      - `{:error, reason}` for other decode errors

      ## Example

          {:ok, data, MyApp.Events.OrderCreated} = MyApp.Dispatch.decode(framed_binary)
      """
      @spec decode(binary()) :: {:ok, map(), module()} | {:error, term()}
      def decode(binary) when is_binary(binary) do
        case GridCodec.Header.decode(binary) do
          {:ok, header, payload} ->
            key = {header.schema_id, header.template_id}

            case Map.get(@dispatch_table, key) do
              nil ->
                {:error, :unknown_message}

              %{module: module, version: max_version} ->
                if header.version > max_version do
                  {:error, {:version_too_new, header.version, max_version}}
                else
                  # Payload doesn't have header, use header: false
                  case module.decode(payload, header: false) do
                    {:ok, data} -> {:ok, data, module}
                    {:error, _} = error -> error
                  end
                end
            end

          {:error, _} = error ->
            error
        end
      end

      @doc """
      Decodes a framed binary message, raising on error.

      ## Example

          {data, codec} = MyApp.Dispatch.decode!(framed_binary)
      """
      @spec decode!(binary()) :: {map(), module()}
      def decode!(binary) when is_binary(binary) do
        case decode(binary) do
          {:ok, data, codec} -> {data, codec}
          {:error, reason} -> raise ArgumentError, "Dispatch decode failed: #{inspect(reason)}"
        end
      end

      @doc """
      Looks up a codec by schema_id and template_id.

      ## Example

          {:ok, MyApp.Events.OrderCreated} = MyApp.Dispatch.lookup(100, 1)
          :error = MyApp.Dispatch.lookup(999, 999)
      """
      @spec lookup(non_neg_integer(), non_neg_integer()) :: {:ok, module()} | :error
      def lookup(schema_id, template_id) do
        case Map.get(@dispatch_table, {schema_id, template_id}) do
          nil -> :error
          %{module: module} -> {:ok, module}
        end
      end

      @doc """
      Lists all registered codec modules.

      ## Example

          [MyApp.Events.OrderCreated, MyApp.Events.OrderFilled] = MyApp.Dispatch.list_codecs()
      """
      @spec list_codecs() :: [module()]
      def list_codecs, do: @codec_modules

      @doc """
      Returns the dispatch table as a map.

      Keys are `{schema_id, template_id}` tuples, values are codec info maps.

      ## Example

          table = MyApp.Dispatch.dispatch_table()
          # %{{100, 1} => %{module: MyApp.Events.OrderCreated, version: 1}, ...}
      """
      @spec dispatch_table() :: %{{non_neg_integer(), non_neg_integer()} => map()}
      def dispatch_table, do: @dispatch_table

      @doc """
      Peeks at the header of a framed message without decoding.

      Useful for routing decisions or logging.

      ## Example

          {:ok, header} = MyApp.Dispatch.peek_header(binary)
          # %{block_length: 32, template_id: 1, schema_id: 100, version: 1}
      """
      @spec peek_header(binary()) :: {:ok, GridCodec.Header.header_info()} | {:error, term()}
      def peek_header(binary) when is_binary(binary) do
        case GridCodec.Header.decode(binary) do
          {:ok, header, _payload} -> {:ok, header}
          {:error, _} = error -> error
        end
      end
    end
  end
end
