defmodule ExampleApp.GroupTailPaddingTest do
  @moduledoc false
  use ExUnit.Case, async: false

  defmodule GroupTailPaddingV1 do
    @moduledoc false
    use GridCodec.Struct,
      template_id: 9920,
      schema_id: 100,
      version: 1,
      name: "GroupTailPaddingV1Writer"

    alias ExampleApp.Events.GroupTailAllocation

    defcodec do
      field :id, :u64

      group :allocations, of: GroupTailAllocation, framing: :length_prefixed
    end
  end

  alias ExampleApp.Events.GroupTailAllocation
  alias ExampleApp.Events.GroupTailPaddingV2
  alias ExampleApp.GroupTailPaddingTest.GroupTailPaddingV1

  test "v1 payload decodes on v2 reader via module decode" do
    v1 = %GroupTailPaddingV1{
      id: 42,
      allocations: [%GroupTailAllocation{qty: 7}]
    }

    {:ok, bin} = GroupTailPaddingV1.encode(v1)

    assert {:ok, out} = GroupTailPaddingV2.decode(bin)
    assert out.id == 42
    assert out.auto_transfer == nil
    assert [%GroupTailAllocation{qty: 7}] = out.allocations
  end

  test "v1 payload decodes via consolidated GridCodec.decode/1" do
    v1 = %GroupTailPaddingV1{
      id: 99,
      allocations: [%GroupTailAllocation{qty: 11}, %GroupTailAllocation{qty: 22}]
    }

    {:ok, bin} = GroupTailPaddingV1.encode(v1)

    assert {:ok, %GroupTailPaddingV2{} = out} = GridCodec.decode(bin)
    assert out.id == 99
    assert out.auto_transfer == nil
    assert [%GroupTailAllocation{qty: 11}, %GroupTailAllocation{qty: 22}] = out.allocations
  end

  test "header-stripped v1 payload decodes on v2 reader" do
    v1 = %GroupTailPaddingV1{
      id: 7,
      allocations: [%GroupTailAllocation{qty: 3}]
    }

    {:ok, bin} = GroupTailPaddingV1.encode(v1)
    {:ok, header, payload} = GridCodec.Header.decode(bin)

    assert {:ok, out} =
             GroupTailPaddingV2.decode(payload,
               header: false,
               __gridcodec_header__: header
             )

    assert out.id == 7
    assert out.auto_transfer == nil
    assert [%GroupTailAllocation{qty: 3}] = out.allocations
  end
end
