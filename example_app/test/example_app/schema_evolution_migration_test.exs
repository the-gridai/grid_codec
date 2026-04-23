defmodule ExampleApp.SchemaEvolutionMigrationTest do
  @moduledoc false
  use ExUnit.Case, async: true

  defmodule MigrationOkV1 do
    use GridCodec.Struct, template_id: 9901, schema_id: 100, version: 1

    defcodec do
      field :id, :u64
      field :units, :u32
    end
  end

  defmodule MigrationOkV2 do
    use GridCodec.Struct,
      template_id: 9901,
      schema_id: 100,
      version: 2,
      field_defaults: [presence: :required, default: 0]

    defcodec do
      field :id, :u64
      field :units, :u32
      field :tenant_id, :u32, since: 2
    end
  end

  defmodule MigrationErrV1 do
    use GridCodec.Struct, template_id: 9902, schema_id: 100, version: 1

    defcodec do
      field :id, :u64
      field :units, :u32
    end
  end

  defmodule MigrationErrV2 do
    use GridCodec.Struct, template_id: 9902, schema_id: 100, version: 2

    defcodec do
      field :id, :u64
      field :units, :u32
      field :tenant_id, :u32, since: 2, presence: :required
    end
  end

  test "v1 payload decodes on v2 when new :since field has field_defaults default" do
    v1 = %MigrationOkV1{id: 10, units: 20}
    {:ok, bin} = MigrationOkV1.encode(v1)

    assert {:ok, out} = MigrationOkV2.decode(bin)
    assert out.id == 10
    assert out.units == 20
    assert out.tenant_id == 0
  end

  test "v1 payload on v2 without decode default fails required_field_absent" do
    v1 = %MigrationErrV1{id: 1, units: 2}
    {:ok, bin} = MigrationErrV1.encode(v1)

    assert {:error, {:required_field_absent, :tenant_id}} = MigrationErrV2.decode(bin)
  end
end
