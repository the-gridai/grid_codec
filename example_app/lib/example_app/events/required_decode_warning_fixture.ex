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

defmodule ExampleApp.Events.RequiredDecodeDefaultOnlyFixture do
  @moduledoc false

  use GridCodec.Struct,
    template_id: 9912,
    version: 1

  defcodec do
    field :id, :u64, presence: :required, default: 42
    field :raw_uuid, :uuid, presence: :required, default: <<1::128>>

    field :uuid_text, :uuid_string,
      presence: :required,
      default: "550e8400-e29b-41d4-a716-446655440000"

    field :string_default, :string, presence: :required, default: "default"
    field :short_text, :string8, presence: :required, default: "short"
    field :medium_text, :string16, presence: :required, default: "legacy"
    field :long_text, :string32, presence: :required, default: "long"
  end
end

defmodule ExampleApp.Events.RequiredDecodeMixedDefaultFixture do
  @moduledoc false

  use GridCodec.Struct,
    template_id: 9913,
    version: 1

  defcodec do
    field :id, :u64, presence: :required
    field :raw_uuid, :uuid

    field :uuid_text, :uuid_string,
      presence: :required,
      default: "550e8400-e29b-41d4-a716-446655440000"

    field :string_default, :string
    field :short_text, :string8
    field :medium_text, :string16, presence: :required
    field :long_text, :string32
  end
end
