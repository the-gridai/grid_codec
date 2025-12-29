defmodule GridCodec.EnvelopeTest do
  use ExUnit.Case

  alias GridCodec.Envelope

  defmodule TestCodec do
    use GridCodec

    defcodec do
      field :id, :u64
      field :price, :u32
      field :active, :bool
    end
  end

  describe "wrap/2" do
    test "creates envelope with binary and codec" do
      binary = TestCodec.encode(%{id: 123, price: 456, active: true})
      env = Envelope.wrap(binary, TestCodec)

      assert %Envelope{} = env
      assert env.binary == binary
      assert env.codec == TestCodec
    end

    test "captures schema metadata" do
      binary = TestCodec.encode(%{id: 1, price: 2, active: false})
      env = Envelope.wrap(binary, TestCodec)

      assert env.schema != nil
      assert env.schema.version == 1
    end
  end

  describe "get/2" do
    test "retrieves field values" do
      binary = TestCodec.encode(%{id: 999, price: 100, active: true})
      env = Envelope.wrap(binary, TestCodec)

      assert Envelope.get(env, :id) == 999
      assert Envelope.get(env, :price) == 100
      assert Envelope.get(env, :active) == true
    end
  end

  describe "get_many/2" do
    test "retrieves multiple fields" do
      binary = TestCodec.encode(%{id: 999, price: 100, active: false})
      env = Envelope.wrap(binary, TestCodec)

      result = Envelope.get_many(env, [:id, :price])
      assert result == %{id: 999, price: 100}
    end
  end

  describe "decode/1" do
    test "fully decodes the binary" do
      data = %{id: 123, price: 456, active: true}
      binary = TestCodec.encode(data)
      env = Envelope.wrap(binary, TestCodec)

      {:ok, decoded} = Envelope.decode(env)
      assert decoded == data
    end
  end

  describe "decode!/1" do
    test "returns map on success" do
      data = %{id: 1, price: 2, active: false}
      binary = TestCodec.encode(data)
      env = Envelope.wrap(binary, TestCodec)

      decoded = Envelope.decode!(env)
      assert decoded == data
    end
  end

  describe "accessors" do
    test "binary/1 returns raw binary" do
      binary = TestCodec.encode(%{id: 1, price: 2, active: true})
      env = Envelope.wrap(binary, TestCodec)

      assert Envelope.binary(env) == binary
    end

    test "codec/1 returns codec module" do
      binary = TestCodec.encode(%{id: 1, price: 2, active: true})
      env = Envelope.wrap(binary, TestCodec)

      assert Envelope.codec(env) == TestCodec
    end

    test "byte_size/1 returns binary size" do
      binary = TestCodec.encode(%{id: 1, price: 2, active: true})
      env = Envelope.wrap(binary, TestCodec)

      # u64 (8) + u32 (4) + bool (1) = 13
      assert Envelope.byte_size(env) == 13
    end

    test "schema/1 returns schema metadata" do
      binary = TestCodec.encode(%{id: 1, price: 2, active: true})
      env = Envelope.wrap(binary, TestCodec)

      schema = Envelope.schema(env)
      assert schema.version == 1
      assert schema.endian == :little
    end
  end
end
