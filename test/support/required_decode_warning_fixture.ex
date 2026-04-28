defmodule GridCodec.TestSupport.RequiredDecodeWarningFixture do
  @moduledoc false
  # Exercises `presence: :required` with nullable built-in decode domains.
  # Keeping this in test/support means `MIX_ENV=test mix compile
  # --warnings-as-errors` catches generated-code coverage regressions.

  use GridCodec.Struct,
    template_id: 9942,
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

defmodule GridCodec.TestSupport.RequiredDecodeWarningOptionalWriter do
  @moduledoc false

  use GridCodec.Struct,
    template_id: 9943,
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

defmodule GridCodec.TestSupport.RequiredDecodeDefaultOnlyFixture do
  @moduledoc false
  # Exercises codecs whose required fields all use decode-time defaults. This
  # shape only calls the generated required helper's /3 arity.

  use GridCodec.Struct,
    template_id: 9944,
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

defmodule GridCodec.TestSupport.RequiredDecodeMixedDefaultFixture do
  @moduledoc false
  # Exercises codecs that need both required helper arities.

  use GridCodec.Struct,
    template_id: 9945,
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
