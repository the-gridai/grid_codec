# Validation Pipeline Benchmark
#
# Compares generated validation pipelines against:
# - hand-rolled struct validation with direct guards
# - generic map validation pipelines built from anonymous functions
# - hand-rolled binary pattern matching
#
# Run with: cd example_app && MIX_ENV=prod mix run benchmarks/validation_bench.exs

defmodule ValidationBench do
  defmodule ValidatedOrderWindow do
    use GridCodec.Struct,
      template_id: 1991,
      schema_id: 199,
      version: 1,
      validate: true

    defcodec do
      field :start_ns, :timestamp_ns
      field :end_ns, :timestamp_ns
      field :quantity, :u32
      field :status, :u8
    end

    validations do
      validate compare(:end_ns, :>=, :start_ns),
        name: :end_after_start,
        category: :invariant

      validate compare(:quantity, :>, 0, allow_nil?: false),
        name: :quantity_positive,
        category: :invariant

      validate one_of(:status, [1, 2]),
        name: :known_status,
        category: :invariant
    end
  end

  defmodule Manual do
    alias ValidationBench.ValidatedOrderWindow

    def validate_struct(%ValidatedOrderWindow{
          start_ns: start_ns,
          end_ns: end_ns,
          quantity: quantity,
          status: status
        }) do
      errors = []
      errors = if is_integer(start_ns) and is_integer(end_ns) and end_ns >= start_ns, do: errors, else: [:end_after_start | errors]
      errors = if is_integer(quantity) and quantity > 0, do: errors, else: [:quantity_positive | errors]
      errors = if status in [1, 2], do: errors, else: [:known_status | errors]

      case Enum.reverse(errors) do
        [] -> :ok
        list -> {:error, list}
      end
    end

    def validate_map(map) when is_map(map) do
      validators = [
        fn attrs ->
          if attrs.end_ns >= attrs.start_ns, do: [], else: [:end_after_start]
        end,
        fn attrs ->
          if attrs.quantity > 0, do: [], else: [:quantity_positive]
        end,
        fn attrs ->
          if attrs.status in [1, 2], do: [], else: [:known_status]
        end
      ]

      errors = Enum.flat_map(validators, fn validator -> validator.(map) end)
      if errors == [], do: :ok, else: {:error, errors}
    end

    def validate_binary(
          <<21::little-16, 1991::little-16, 199::little-16, 1::little-16, start_ns::little-signed-64,
            end_ns::little-signed-64, quantity::little-unsigned-32, status::unsigned-8>>
        ) do
      errors = []
      errors = if end_ns >= start_ns, do: errors, else: [:end_after_start | errors]
      errors = if quantity > 0, do: errors, else: [:quantity_positive | errors]
      errors = if status in [1, 2], do: errors, else: [:known_status | errors]

      case Enum.reverse(errors) do
        [] -> :ok
        list -> {:error, list}
      end
    end
  end

  def run do
    IO.puts("Validation Pipeline Benchmark")
    IO.puts("================================\n")
    IO.puts("This benchmark compares GridCodec generated validation against hand-rolled")
    IO.puts("struct checks, hand-rolled binary checks, and generic map validation")
    IO.puts("pipelines built from anonymous functions.\n")

    valid_attrs = %{
      start_ns: 1_700_000_000_000_000_000,
      end_ns: 1_700_000_000_100_000_000,
      quantity: 250,
      status: 1
    }

    invalid_attrs = %{
      start_ns: 1_700_000_000_100_000_000,
      end_ns: 1_700_000_000_000_000_000,
      quantity: 0,
      status: 9
    }

    {:ok, valid_struct} = ValidatedOrderWindow.new(valid_attrs)
    {:ok, invalid_struct} = ValidatedOrderWindow.new(%{valid_attrs | status: 1, quantity: 1})
    invalid_struct = %{invalid_struct | end_ns: invalid_attrs.end_ns, quantity: invalid_attrs.quantity, status: invalid_attrs.status}

    {:ok, valid_binary} = ValidatedOrderWindow.encode(valid_struct)
    <<header::binary-size(8), _::binary>> = valid_binary

    invalid_binary =
      <<header::binary, invalid_attrs.start_ns::little-signed-64, invalid_attrs.end_ns::little-signed-64,
        invalid_attrs.quantity::little-unsigned-32, invalid_attrs.status::unsigned-8>>

    IO.puts("Wire size: #{byte_size(valid_binary)} bytes")
    IO.puts("Validators: end_after_start, quantity_positive, known_status\n")

    run_struct_happy_bench(valid_struct)
    run_struct_invalid_bench(invalid_struct)
    run_binary_happy_bench(valid_binary, valid_struct)
    run_binary_invalid_bench(invalid_binary, invalid_struct)
  end

  defp run_struct_happy_bench(valid_struct) do
    IO.puts("--- Struct validation (happy path) ---\n")

    map = Map.from_struct(valid_struct)

    Benchee.run(
      %{
        "generated validate_struct/1" => fn ->
          {:ok, _struct} = ValidatedOrderWindow.validate_struct(valid_struct)
        end,
        "hand-rolled struct validation" => fn ->
          :ok = Manual.validate_struct(valid_struct)
        end,
        "map validators (anonymous fns)" => fn ->
          :ok = Manual.validate_map(map)
        end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )
  end

  defp run_struct_invalid_bench(invalid_struct) do
    IO.puts("\n--- Struct validation (accumulating failure path) ---\n")

    map = Map.from_struct(invalid_struct)

    Benchee.run(
      %{
        "generated validate_struct/1" => fn ->
          {:error, _} = ValidatedOrderWindow.validate_struct(invalid_struct)
        end,
        "hand-rolled struct validation" => fn ->
          {:error, _} = Manual.validate_struct(invalid_struct)
        end,
        "map validators (anonymous fns)" => fn ->
          {:error, _} = Manual.validate_map(map)
        end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )
  end

  defp run_binary_happy_bench(valid_binary, valid_struct) do
    IO.puts("\n--- Binary validation (happy path) ---\n")

    Benchee.run(
      %{
        "generated validate_binary/1" => fn ->
          :ok = ValidatedOrderWindow.validate_binary(valid_binary)
        end,
        "hand-rolled binary pattern" => fn ->
          :ok = Manual.validate_binary(valid_binary)
        end,
        "decode + hand-rolled struct validation" => fn ->
          {:ok, decoded} = ValidatedOrderWindow.decode(valid_binary)
          :ok = Manual.validate_struct(decoded)
        end,
        "validate_struct/1 on decoded struct" => fn ->
          {:ok, _struct} = ValidatedOrderWindow.validate_struct(valid_struct)
        end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )
  end

  defp run_binary_invalid_bench(invalid_binary, invalid_struct) do
    IO.puts("\n--- Binary validation (accumulating failure path) ---\n")

    Benchee.run(
      %{
        "generated validate_binary/1" => fn ->
          {:error, _} = ValidatedOrderWindow.validate_binary(invalid_binary)
        end,
        "hand-rolled binary pattern" => fn ->
          {:error, _} = Manual.validate_binary(invalid_binary)
        end,
        "decode + hand-rolled struct validation" => fn ->
          {:ok, decoded} = ValidatedOrderWindow.decode(invalid_binary)
          {:error, _} = Manual.validate_struct(decoded)
        end,
        "validate_struct/1 on invalid struct" => fn ->
          {:error, _} = ValidatedOrderWindow.validate_struct(invalid_struct)
        end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )
  end
end

ValidationBench.run()
