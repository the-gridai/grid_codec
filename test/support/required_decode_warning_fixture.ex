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
