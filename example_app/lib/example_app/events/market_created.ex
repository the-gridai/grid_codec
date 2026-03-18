defmodule ExampleApp.Events.MarketCreated do
  @moduledoc "Example event with multiple string fields to test var-field offset chaining."
  use GridCodec.Struct, template_id: 3, schema_id: 100, name: "MarketCreated"

  defcodec do
    field :market_id, :uuid, doc: "Stable identifier for the newly created market."
    field :active, :bool, doc: "Whether the market is immediately tradable."
    field :name, :string16, doc: "Human-readable market name."
    field :description, :string16, doc: "Longer description shown in clients or admin tools."
    field :category, :string16, doc: "Market category used for grouping and discovery."
  end
end
