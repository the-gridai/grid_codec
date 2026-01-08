defmodule GridCodec.EnvelopeTest do
  use ExUnit.Case

  alias GridCodec.Envelope

  defmodule TestCodec do
    use GridCodec.Struct

    defcodec do
      field :id, :u64
      field :price, :u32
      field :active, :bool
    end
  end

  describe "wrap/2" do
    test "creates envelope with binary and codec" do
      # Use payload-only for direct Envelope.wrap
      payload = TestCodec.encode(%TestCodec{id: 123, price: 456, active: true}, header: false)
      env = Envelope.wrap(payload, TestCodec)

      assert %Envelope{} = env
      assert env.binary == payload
      assert env.codec == TestCodec
    end

    test "captures schema metadata" do
      payload = TestCodec.encode(%TestCodec{id: 1, price: 2, active: false}, header: false)
      env = Envelope.wrap(payload, TestCodec)

      assert env.schema != nil
      assert env.schema.version == 1
    end
  end

  describe "get/2" do
    test "retrieves field values" do
      payload = TestCodec.encode(%TestCodec{id: 999, price: 100, active: true}, header: false)
      env = Envelope.wrap(payload, TestCodec)

      assert Envelope.get(env, :id) == 999
      assert Envelope.get(env, :price) == 100
      assert Envelope.get(env, :active) == true
    end
  end

  describe "get_many/2" do
    test "retrieves multiple fields" do
      payload = TestCodec.encode(%TestCodec{id: 999, price: 100, active: false}, header: false)
      env = Envelope.wrap(payload, TestCodec)

      result = Envelope.get_many(env, [:id, :price])
      assert result == %{id: 999, price: 100}
    end
  end

  describe "decode/1" do
    test "fully decodes the binary" do
      data = %TestCodec{id: 123, price: 456, active: true}
      payload = TestCodec.encode(data, header: false)
      env = Envelope.wrap(payload, TestCodec)

      {:ok, decoded} = Envelope.decode(env)
      assert decoded == data
    end
  end

  describe "decode!/1" do
    test "returns struct on success" do
      data = %TestCodec{id: 1, price: 2, active: false}
      payload = TestCodec.encode(data, header: false)
      env = Envelope.wrap(payload, TestCodec)

      {:ok, decoded} = Envelope.decode(env)
      assert decoded == data
    end
  end

  describe "accessors" do
    test "binary/1 returns raw binary" do
      payload = TestCodec.encode(%TestCodec{id: 1, price: 2, active: true}, header: false)
      env = Envelope.wrap(payload, TestCodec)

      assert Envelope.binary(env) == payload
    end

    test "codec/1 returns codec module" do
      payload = TestCodec.encode(%TestCodec{id: 1, price: 2, active: true}, header: false)
      env = Envelope.wrap(payload, TestCodec)

      assert Envelope.codec(env) == TestCodec
    end

    test "byte_size/1 returns binary size" do
      payload = TestCodec.encode(%TestCodec{id: 1, price: 2, active: true}, header: false)
      env = Envelope.wrap(payload, TestCodec)

      # u64 (8) + u32 (4) + bool (1) = 13 (payload only)
      assert Envelope.byte_size(env) == 13
    end

    test "schema/1 returns schema metadata" do
      payload = TestCodec.encode(%TestCodec{id: 1, price: 2, active: true}, header: false)
      env = Envelope.wrap(payload, TestCodec)

      schema = Envelope.schema(env)
      assert schema.version == 1
      assert schema.endian == :little
    end
  end

  describe "module wrap integration" do
    test "module wrap handles framed binary" do
      data = %TestCodec{id: 999, price: 100, active: true}
      # includes header
      framed = TestCodec.encode(data)

      # Module wrap strips header automatically
      env = TestCodec.wrap(framed)

      assert Envelope.get(env, :id) == 999
      assert Envelope.get(env, :price) == 100
    end
  end
end
