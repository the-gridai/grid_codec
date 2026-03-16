defmodule GridCodec.ScalarGroupTest do
  use ExUnit.Case, async: true

  defmodule FixedScalarContainer do
    use GridCodec.Struct, template_id: 9100, schema_id: 91, version: 1

    defcodec do
      field :name, :string16

      group :tag_ids, of: :uuid
      group :scores, of: :u32
    end
  end

  defmodule VariableScalarContainer do
    use GridCodec.Struct, template_id: 9101, schema_id: 91, version: 1

    defcodec do
      field :label, :string16

      group :names, of: :string16
    end
  end

  defmodule MixedContainer do
    use GridCodec.Struct, template_id: 9102, schema_id: 91, version: 1

    defcodec do
      field :account_id, :u64

      group :tag_ids, of: :uuid
      group :labels, of: :string16
      group :priorities, of: :u64
    end
  end

  describe "fixed-size scalar group (uuid)" do
    test "roundtrip with UUIDs" do
      uuid1 = <<1::128>>
      uuid2 = <<2::128>>
      uuid3 = <<3::128>>

      container = %FixedScalarContainer{
        name: "test",
        tag_ids: [uuid1, uuid2, uuid3],
        scores: [100, 200, 300]
      }

      {:ok, binary} = FixedScalarContainer.encode(container)
      {:ok, decoded} = FixedScalarContainer.decode(binary)

      assert decoded.name == "test"
      assert decoded.tag_ids == [uuid1, uuid2, uuid3]
      assert decoded.scores == [100, 200, 300]
    end

    test "roundtrip with empty list" do
      container = %FixedScalarContainer{
        name: "empty",
        tag_ids: [],
        scores: []
      }

      {:ok, binary} = FixedScalarContainer.encode(container)
      {:ok, decoded} = FixedScalarContainer.decode(binary)

      assert decoded.name == "empty"
      assert decoded.tag_ids == []
      assert decoded.scores == []
    end

    test "roundtrip with nil UUIDs in list" do
      uuid1 = <<1::128>>

      container = %FixedScalarContainer{
        name: "nils",
        tag_ids: [uuid1, nil, <<3::128>>],
        scores: [0, 42]
      }

      {:ok, binary} = FixedScalarContainer.encode(container)
      {:ok, decoded} = FixedScalarContainer.decode(binary)

      assert decoded.tag_ids == [uuid1, nil, <<3::128>>]
      assert decoded.scores == [0, 42]
    end
  end

  describe "variable-length scalar group (string)" do
    test "roundtrip with strings" do
      container = %VariableScalarContainer{
        label: "my-list",
        names: ["alice", "bob", "charlie"]
      }

      {:ok, binary} = VariableScalarContainer.encode(container)
      {:ok, decoded} = VariableScalarContainer.decode(binary)

      assert decoded.label == "my-list"
      assert decoded.names == ["alice", "bob", "charlie"]
    end

    test "roundtrip with empty list" do
      container = %VariableScalarContainer{
        label: "empty",
        names: []
      }

      {:ok, binary} = VariableScalarContainer.encode(container)
      {:ok, decoded} = VariableScalarContainer.decode(binary)

      assert decoded.label == "empty"
      assert decoded.names == []
    end

    test "roundtrip with varying lengths" do
      container = %VariableScalarContainer{
        label: "varied",
        names: ["a", String.duplicate("x", 1000), "short"]
      }

      {:ok, binary} = VariableScalarContainer.encode(container)
      {:ok, decoded} = VariableScalarContainer.decode(binary)

      assert decoded.names == ["a", String.duplicate("x", 1000), "short"]
    end

    test "nil strings encode as null sentinel" do
      container = %VariableScalarContainer{
        label: "nils",
        names: ["hello", nil, "world"]
      }

      {:ok, binary} = VariableScalarContainer.encode(container)
      {:ok, decoded} = VariableScalarContainer.decode(binary)

      assert decoded.names == ["hello", nil, "world"]
    end
  end

  describe "mixed scalar + fixed groups" do
    test "roundtrip with uuids, strings, and integers" do
      uuid1 = <<10::128>>
      uuid2 = <<20::128>>

      container = %MixedContainer{
        account_id: 999,
        tag_ids: [uuid1, uuid2],
        labels: ["important", "archived"],
        priorities: [1, 2, 3]
      }

      {:ok, binary} = MixedContainer.encode(container)
      {:ok, decoded} = MixedContainer.decode(binary)

      assert decoded.account_id == 999
      assert decoded.tag_ids == [uuid1, uuid2]
      assert decoded.labels == ["important", "archived"]
      assert decoded.priorities == [1, 2, 3]
    end
  end

  describe "new/1 coercion" do
    test "accepts list for scalar groups" do
      uuid = <<1::128>>
      {:ok, container} = FixedScalarContainer.new(%{name: "test", tag_ids: [uuid], scores: [5]})

      assert container.tag_ids == [uuid]
      assert container.scores == [5]
    end

    test "defaults to empty list" do
      {:ok, container} = FixedScalarContainer.new(%{name: "test"})
      assert container.tag_ids == []
      assert container.scores == []
    end

    test "nil becomes empty list" do
      {:ok, container} = FixedScalarContainer.new(%{name: "test", tag_ids: nil})
      assert container.tag_ids == []
    end

    test "accepts string keys" do
      {:ok, container} = VariableScalarContainer.new(%{"label" => "test", "names" => ["a", "b"]})
      assert container.names == ["a", "b"]
    end
  end

  describe "schema introspection" do
    test "fixed scalar group reports of: in schema" do
      schema = FixedScalarContainer.__schema__()
      tag_group = Enum.find(schema.groups, fn {name, _, _} -> name == :tag_ids end)
      assert tag_group != nil
      {_, _, opts} = tag_group
      assert Keyword.get(opts, :of) == :uuid
    end

    test "variable scalar group reports of: and framing" do
      schema = VariableScalarContainer.__schema__()
      names_group = Enum.find(schema.groups, fn {name, _, _} -> name == :names end)
      assert names_group != nil
      {_, _, opts} = names_group
      assert Keyword.get(opts, :of) == :string16
      assert Keyword.get(opts, :framing) == :length_prefixed
    end
  end
end
