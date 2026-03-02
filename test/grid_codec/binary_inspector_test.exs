defmodule GridCodec.BinaryInspectorTest do
  use ExUnit.Case, async: true

  alias GridCodec.BinaryInspector

  defmodule InspectorCodec do
    use GridCodec.Struct, template_id: 8801, schema_id: 77

    defcodec do
      field :id, :u64
      field :price, :u32
      field :delta, :i16
      field :note, :string16
    end
  end

  test "inspects framed binary with explicit schema" do
    binary =
      InspectorCodec.encode(%InspectorCodec{
        id: 123,
        price: 456,
        delta: -3,
        note: "hello"
      })

    assert {:ok, inspected} = BinaryInspector.inspect(binary, schema: InspectorCodec)
    assert inspected.schema == InspectorCodec
    assert inspected.header.template_id == 8801
    assert inspected.header.schema_id == 77
    assert inspected.fixed_block_size == InspectorCodec.block_length()
    assert inspected.variable_fields == [:note]

    assert Enum.map(inspected.fixed_fields, & &1.name) == [:id, :price, :delta]
    assert Enum.map(inspected.fixed_fields, & &1.value) == [123, 456, -3]
  end

  test "inspects framed binary with registry dispatch" do
    binary =
      InspectorCodec.encode(%InspectorCodec{
        id: 1,
        price: 2,
        delta: 3,
        note: "x"
      })

    assert {:ok, inspected} = BinaryInspector.inspect(binary)
    assert inspected.schema == InspectorCodec
    assert inspected.header.template_id == 8801
  end

  test "inspects payload-only binary when schema provided" do
    payload =
      InspectorCodec.encode(%InspectorCodec{id: 9, price: 10, delta: 11, note: "z"},
        header: false
      )

    assert {:ok, inspected} =
             BinaryInspector.inspect(payload, schema: InspectorCodec, header: false)

    assert inspected.header == nil
    assert Enum.map(inspected.fixed_fields, & &1.value) == [9, 10, 11]
  end

  test "errors when schema missing for payload-only mode" do
    payload =
      InspectorCodec.encode(%InspectorCodec{id: 1, price: 1, delta: 1, note: "a"}, header: false)

    assert {:error, :schema_required_without_header} =
             BinaryInspector.inspect(payload, header: false)
  end
end
