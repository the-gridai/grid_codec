defmodule GridCodec.TelemetryTest do
  use ExUnit.Case, async: true

  defmodule WithTelemetry do
    use GridCodec.Struct,
      template_id: 850,
      schema_id: 60,
      version: 1,
      name: "WithTelemetry",
      telemetry: true

    defcodec do
      field :id, :u64
      field :price, :u64
      field :name, :string
    end
  end

  defmodule WithoutTelemetry do
    use GridCodec.Struct,
      template_id: 851,
      schema_id: 60,
      version: 1,
      name: "WithoutTelemetry",
      telemetry: false

    defcodec do
      field :id, :u64
    end
  end

  defmodule Handler do
    def handle_event(event, measurements, metadata, pid) do
      send(pid, {:telemetry_event, event, measurements, metadata})
    end
  end

  setup do
    test_pid = self()

    :telemetry.attach(
      "test-encode-#{inspect(test_pid)}",
      [:grid_codec, :encode],
      &Handler.handle_event/4,
      test_pid
    )

    :telemetry.attach(
      "test-decode-#{inspect(test_pid)}",
      [:grid_codec, :decode],
      &Handler.handle_event/4,
      test_pid
    )

    on_exit(fn ->
      :telemetry.detach("test-encode-#{inspect(test_pid)}")
      :telemetry.detach("test-decode-#{inspect(test_pid)}")
    end)
  end

  describe "encode telemetry" do
    test "emits [:grid_codec, :encode] event with duration and bytes" do
      struct = %WithTelemetry{id: 42, price: 100, name: "test"}
      {:ok, _binary} = WithTelemetry.encode(struct)

      assert_receive {:telemetry_event, [:grid_codec, :encode], measurements, metadata}

      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert is_integer(measurements.bytes)
      assert measurements.bytes > 0

      assert metadata.module == WithTelemetry
      assert metadata.type_name == "WithTelemetry"
      assert metadata.schema_id == 60
      assert metadata.template_id == 850
    end

    test "emits for encode with header: false" do
      struct = %WithTelemetry{id: 42, price: 100, name: "test"}
      {:ok, _binary} = WithTelemetry.encode(struct, header: false)

      assert_receive {:telemetry_event, [:grid_codec, :encode], measurements, _metadata}
      assert measurements.bytes > 0
    end

    test "bytes reflects actual binary size" do
      struct = %WithTelemetry{id: 42, price: 100, name: "test"}
      {:ok, binary} = WithTelemetry.encode(struct)

      assert_receive {:telemetry_event, [:grid_codec, :encode], measurements, _metadata}
      assert measurements.bytes == byte_size(binary)
    end
  end

  describe "decode telemetry" do
    test "emits [:grid_codec, :decode] event with duration and bytes" do
      struct = %WithTelemetry{id: 42, price: 100, name: "test"}
      {:ok, binary} = WithTelemetry.encode(struct)

      # Clear encode event
      assert_receive {:telemetry_event, [:grid_codec, :encode], _, _}

      {:ok, _decoded} = WithTelemetry.decode(binary)

      assert_receive {:telemetry_event, [:grid_codec, :decode], measurements, metadata}

      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert measurements.bytes == byte_size(binary)

      assert metadata.module == WithTelemetry
      assert metadata.type_name == "WithTelemetry"
      assert metadata.schema_id == 60
      assert metadata.template_id == 850
    end

    test "emits for decode with header: false" do
      struct = %WithTelemetry{id: 42, price: 100, name: "test"}
      {:ok, binary} = WithTelemetry.encode(struct, header: false)

      # Clear encode event
      assert_receive {:telemetry_event, [:grid_codec, :encode], _, _}

      {:ok, _decoded} = WithTelemetry.decode(binary, header: false)

      assert_receive {:telemetry_event, [:grid_codec, :decode], measurements, _metadata}
      assert measurements.bytes == byte_size(binary)
    end
  end

  describe "telemetry disabled" do
    test "no events emitted when telemetry: false" do
      struct = %WithoutTelemetry{id: 42}
      {:ok, binary} = WithoutTelemetry.encode(struct)
      {:ok, _decoded} = WithoutTelemetry.decode(binary)

      refute_receive {:telemetry_event, _, _, _}, 10
    end
  end
end
