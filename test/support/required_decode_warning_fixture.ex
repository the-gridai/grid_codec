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

defmodule GridCodec.TestSupport.RequiredServiceFamilyName do
  @moduledoc false
  @behaviour GridCodec.Type

  @impl true
  def size, do: :variable

  @impl true
  def alignment, do: 1

  @impl true
  def null_value, do: nil

  @impl true
  def encode_ast(_field_name, _default, _endian, _data_var),
    do: raise("variable string wrappers are encoded by the compiler var-data section")

  @impl true
  def decode_pattern_ast(_var, _endian),
    do: raise("variable string wrappers are decoded by the compiler var-data section")

  @impl true
  def getter_ast(_offset, _endian, _payload_var), do: nil
end

defmodule GridCodec.TestSupport.RequiredModelFamilyName do
  @moduledoc false
  @behaviour GridCodec.Type

  @impl true
  def size, do: :variable

  @impl true
  def alignment, do: 1

  @impl true
  def null_value, do: nil

  @impl true
  def encode_ast(_field_name, _default, _endian, _data_var),
    do: raise("variable string wrappers are encoded by the compiler var-data section")

  @impl true
  def decode_pattern_ast(_var, _endian),
    do: raise("variable string wrappers are decoded by the compiler var-data section")

  @impl true
  def getter_ast(_offset, _endian, _payload_var), do: nil
end

defmodule GridCodec.TestSupport.RequiredUnitName do
  @moduledoc false
  @behaviour GridCodec.Type

  @impl true
  def size, do: :variable

  @impl true
  def alignment, do: 1

  @impl true
  def null_value, do: nil

  @impl true
  def encode_ast(_field_name, _default, _endian, _data_var),
    do: raise("variable string wrappers are encoded by the compiler var-data section")

  @impl true
  def decode_pattern_ast(_var, _endian),
    do: raise("variable string wrappers are decoded by the compiler var-data section")

  @impl true
  def getter_ast(_offset, _endian, _payload_var), do: nil
end

defmodule GridCodec.TestSupport.RequiredInlineStringWrapperFixture do
  @moduledoc false

  alias GridCodec.TestSupport.RequiredModelFamilyName
  alias GridCodec.TestSupport.RequiredServiceFamilyName
  alias GridCodec.TestSupport.RequiredUnitName

  use GridCodec.Struct,
    template_id: 9946,
    version: 1

  defcodec do
    field :service_family, RequiredServiceFamilyName, presence: :required
    field :model_family, RequiredModelFamilyName, presence: :required
    field :unit_name, RequiredUnitName, presence: :required
  end
end
