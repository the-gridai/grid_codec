defmodule ExampleApp.Events.MarketCreated do
  @moduledoc "Example event with multiple string fields to test var-field offset chaining."
  use GridCodec.Struct, template_id: 3, schema_id: 100, name: "MarketCreated"

  defcodec do
    field :market_id, :uuid
    field :active, :bool
    field :name, :string16
    field :description, :string16
    field :category, :string16
  end
end
