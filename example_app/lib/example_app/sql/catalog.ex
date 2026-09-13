defmodule ExampleApp.SQL.Catalog do
  @moduledoc """
  Host-owned PostgreSQL stream functions for an event envelope table.

  GridCodec generates codec catalogs. This module binds those codecs to the
  table this application owns. It is the consumer pattern for mixed-type
  paging and the unfiltered stream-version companion.
  """

  alias ExampleApp.Events.OrderCreated
  alias ExampleApp.Events.TradeExecuted
  alias GridCodec.SQL

  @default_table "public.events"
  @stream_id_type :text

  @jsonb_stream "public.decode_event_stream"
  @raw_stream "public.read_event_stream"
  @projected_stream "public.read_order_stream"
  @typed_stream "public.read_typed_order_stream"
  @mixed_stream "public.read_market_stream"
  @mixed_stream_version "public.read_market_stream_version"

  @doc "JSONB whole-stream decoder function name."
  def jsonb_stream_function, do: @jsonb_stream

  @doc "Raw whole-stream reader function name."
  def raw_stream_function, do: @raw_stream

  @doc "Fixed-field OrderCreated projection function name."
  def projected_stream_function, do: @projected_stream

  @doc "Native typed OrderCreated projection function name."
  def typed_stream_function, do: @typed_stream

  @doc "Mixed-type raw market stream function name."
  def mixed_stream_function, do: @mixed_stream

  @doc "Unfiltered stream-version companion function name."
  def mixed_stream_version_function, do: @mixed_stream_version

  @doc """
  Returns CREATE statements for the example stream API.

  Pass `:table` when the envelope table is not `public.events`.
  """
  def install_statements(opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)

    [
      SQL.generate_stream_decoder(jsonb_opts(table)),
      SQL.generate_stream_decoder(raw_opts(table)),
      SQL.generate_stream_decoder(projected_opts(table)),
      SQL.generate_stream_decoder(typed_opts(table)),
      SQL.generate_stream_decoder(mixed_opts(table)),
      SQL.generate_stream_version(version_opts(table))
    ]
  end

  @doc """
  Returns drop statements for the example stream API.

  Decoder drops are single `DO` blocks that remove both the legacy 1-argument
  overload and the paged 3-argument form.
  """
  def drop_statements(opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)

    [
      SQL.drop_stream_decoder_statement(jsonb_opts(table)),
      SQL.drop_stream_decoder_statement(raw_opts(table)),
      SQL.drop_stream_decoder_statement(projected_opts(table)),
      SQL.drop_stream_decoder_statement(typed_opts(table)),
      SQL.drop_stream_decoder_statement(mixed_opts(table)),
      SQL.drop_stream_version_statement(version_opts(table))
    ]
  end

  defp jsonb_opts(table) do
    [function: @jsonb_stream, table: table, stream_id_type: @stream_id_type]
  end

  defp raw_opts(table) do
    [
      function: @raw_stream,
      table: table,
      stream_id_type: @stream_id_type,
      decode: :raw
    ]
  end

  defp projected_opts(table) do
    [
      function: @projected_stream,
      table: table,
      stream_id_type: @stream_id_type,
      decode: {:fields, OrderCreated, [:side, :price, :quantity]}
    ]
  end

  defp typed_opts(table) do
    [
      function: @typed_stream,
      table: table,
      stream_id_type: @stream_id_type,
      decode: {:typed, OrderCreated}
    ]
  end

  defp mixed_opts(table) do
    [
      function: @mixed_stream,
      table: table,
      stream_id_type: @stream_id_type,
      decode: {:raw, [OrderCreated, TradeExecuted]}
    ]
  end

  defp version_opts(table) do
    [
      function: @mixed_stream_version,
      table: table,
      stream_id_type: @stream_id_type
    ]
  end
end
