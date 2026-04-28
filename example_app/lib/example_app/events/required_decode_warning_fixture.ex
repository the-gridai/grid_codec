defmodule ExampleApp.Events.RequiredDecodeWarningFixture do
  @moduledoc """
  Example-app regression codec for required nullable built-in decode paths.

  It is intentionally compiled with the application (not only tests) so
  `mix compile --warnings-as-errors` and `mix dialyzer` cover the same generated
  code shape that downstream apps consume.
  """

  use GridCodec.Struct,
    template_id: 9910,
    version: 1,
    field_defaults: [presence: :required]

  defcodec do
    field :id, :u64
    field :raw_uuid, :uuid
    field :uuid_text, :uuid_string
    field :string_default, :string
    field :short_text, :string8
    field :medium_text, :string16
    field :long_text, :string32
  end
end

defmodule ExampleApp.Events.RequiredDecodeWarningOptionalWriter do
  @moduledoc false

  use GridCodec.Struct,
    template_id: 9911,
    version: 1

  defcodec do
    field :id, :u64
    field :raw_uuid, :uuid
    field :uuid_text, :uuid_string
    field :string_default, :string
    field :short_text, :string8
    field :medium_text, :string16
    field :long_text, :string32
  end
end
