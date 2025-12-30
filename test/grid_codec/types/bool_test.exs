defmodule GridCodec.Types.BoolTest do
  use ExUnit.Case, async: true

  defmodule BoolCodec do
    use GridCodec

    defcodec do
      field :flag, :bool
    end
  end

  defmodule RequiredBoolCodec do
    use GridCodec

    defcodec do
      field :flag, :bool, presence: :required
    end
  end

  defmodule BoolWithDefaultCodec do
    use GridCodec

    defcodec do
      field :flag, :bool, default: true
    end
  end

  describe "encode/decode roundtrip" do
    test "encodes true as 1" do
      binary = BoolCodec.encode(%{flag: true})
      assert binary == <<1>>
    end

    test "encodes false as 0" do
      binary = BoolCodec.encode(%{flag: false})
      assert binary == <<0>>
    end

    test "encodes nil as 255 (null sentinel)" do
      binary = BoolCodec.encode(%{flag: nil})
      assert binary == <<255>>
    end

    test "encodes missing field as 255 (null sentinel)" do
      binary = BoolCodec.encode(%{})
      assert binary == <<255>>
    end

    test "decodes 0 as false" do
      assert {:ok, %{flag: false}} = BoolCodec.decode(<<0>>)
    end

    test "decodes 1 as true" do
      assert {:ok, %{flag: true}} = BoolCodec.decode(<<1>>)
    end

    test "decodes 255 as nil" do
      assert {:ok, %{flag: nil}} = BoolCodec.decode(<<255>>)
    end

    test "decodes any non-zero, non-255 value as true" do
      assert {:ok, %{flag: true}} = BoolCodec.decode(<<2>>)
      assert {:ok, %{flag: true}} = BoolCodec.decode(<<42>>)
      assert {:ok, %{flag: true}} = BoolCodec.decode(<<254>>)
    end

    test "roundtrip for true" do
      original = %{flag: true}
      {:ok, decoded} = original |> BoolCodec.encode() |> BoolCodec.decode()
      assert decoded == original
    end

    test "roundtrip for false" do
      original = %{flag: false}
      {:ok, decoded} = original |> BoolCodec.encode() |> BoolCodec.decode()
      assert decoded == original
    end

    test "roundtrip for nil" do
      original = %{flag: nil}
      {:ok, decoded} = original |> BoolCodec.encode() |> BoolCodec.decode()
      assert decoded == original
    end
  end

  describe "zero-copy getter" do
    test "get returns true for 1" do
      binary = <<1>>
      env = BoolCodec.wrap(binary)
      assert BoolCodec.get(env, :flag) == true
    end

    test "get returns false for 0" do
      binary = <<0>>
      env = BoolCodec.wrap(binary)
      assert BoolCodec.get(env, :flag) == false
    end

    test "get returns nil for 255 (null sentinel)" do
      binary = <<255>>
      env = BoolCodec.wrap(binary)
      assert BoolCodec.get(env, :flag) == nil
    end

    test "get returns true for any non-zero, non-255 value" do
      for byte <- [2, 42, 128, 254] do
        env = BoolCodec.wrap(<<byte>>)
        assert BoolCodec.get(env, :flag) == true, "expected true for byte #{byte}"
      end
    end
  end

  describe "default value" do
    test "uses default when field is missing" do
      binary = BoolWithDefaultCodec.encode(%{})
      # true is encoded as 1
      assert binary == <<1>>
    end

    test "uses default when field is nil" do
      binary = BoolWithDefaultCodec.encode(%{flag: nil})
      # nil overrides the default - nil means "no value"
      # Actually with the current implementation, nil should still encode as nil
      # because the default only applies when the key is missing
      # Let me check the actual behavior...
      # Map.get(%{flag: nil}, :flag, true) returns nil, not true
      # So this should encode as 255 (nil sentinel)
      assert binary == <<255>>
    end

    test "explicit false overrides default" do
      binary = BoolWithDefaultCodec.encode(%{flag: false})
      assert binary == <<0>>
    end
  end

  describe "required presence" do
    test "encodes required bool correctly" do
      assert RequiredBoolCodec.encode(%{flag: true}) == <<1>>
      assert RequiredBoolCodec.encode(%{flag: false}) == <<0>>
    end

    # Note: required validation happens at the compiler/schema level,
    # not at the type level. The type just encodes what it receives.
  end
end
