defmodule GridCodec.TestSupport.RequiredCharArrayFixture do
  @moduledoc false
  # Exercises `presence: :required` with `GridCodec.Types.CharArray` in `lib/`
  # compile paths (`MIX_ENV=test` includes `test/support`). Ensures the
  # generated decoder compiles under `mix compile --warnings-as-errors`
  # (see issue #14).

  defmodule Code4 do
    @moduledoc false
    use GridCodec.Types.CharArray, length: 4
  end

  use GridCodec.Struct,
    template_id: 9932,
    schema_id: 993,
    version: 1,
    field_defaults: [presence: :required]

  defcodec do
    field :id, :u64
    field :code, Code4
  end
end
