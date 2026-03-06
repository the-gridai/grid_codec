defmodule GridCodec.BatchTest do
  use ExUnit.Case, async: true

  alias GridCodec.Batch.PaddedUnion
  alias GridCodec.Batch.TypedFrames
  alias GridCodec.Batch.PerTypeGroups

  alias GridCodec.TestSupport.Batch.SmallCommand
  alias GridCodec.TestSupport.Batch.MediumCommand
  alias GridCodec.TestSupport.Batch.LargeCommand

  @small_bl SmallCommand.block_length()
  @medium_bl MediumCommand.block_length()
  @large_bl LargeCommand.block_length()

  @type_specs [
    {0, SmallCommand, @small_bl},
    {1, MediumCommand, @medium_bl},
    {2, LargeCommand, @large_bl}
  ]

  defp make_small(id) do
    %SmallCommand{order_id: id, timestamp: System.system_time(:microsecond)}
  end

  defp make_medium(id) do
    %MediumCommand{
      order_id: id,
      user_id: 42,
      symbol: <<1::128>>,
      price: 10_000,
      quantity: 100,
      flags: 0
    }
  end

  defp make_large(id) do
    %LargeCommand{
      order_id: id,
      user_id: 42,
      symbol: <<2::128>>,
      price: 10_000,
      quantity: 500,
      limit_price: 10_050,
      stop_price: 9_950,
      flags: 1,
      side: 0,
      order_type: 1,
      time_in_force: 2,
      reserved: 0,
      timestamp: System.system_time(:microsecond)
    }
  end

  defp mixed_entries(0), do: []

  defp mixed_entries(n) do
    Enum.map(0..(n - 1)//1, fn i ->
      case rem(i, 3) do
        0 -> make_large(i)
        1 -> make_medium(i)
        2 -> make_small(i)
      end
    end)
  end

  defp expected_tag(%SmallCommand{}), do: 0
  defp expected_tag(%MediumCommand{}), do: 1
  defp expected_tag(%LargeCommand{}), do: 2

  defp strip_struct(entry) when is_struct(entry), do: Map.from_struct(entry)
  defp strip_struct(entry) when is_map(entry), do: entry

  defp entries_equal?(original, decoded) do
    strip_struct(original) == strip_struct(decoded)
  end

  # ----------------------------------------------------------------
  # Block length sanity
  # ----------------------------------------------------------------

  test "test codecs have expected block lengths" do
    assert SmallCommand.block_length() == 16
    assert MediumCommand.block_length() == 48
    assert LargeCommand.block_length() == 80
  end

  # ----------------------------------------------------------------
  # Roundtrip tests — run same assertions for all 3 architectures
  # ----------------------------------------------------------------

  describe "roundtrip" do
    for {arch_name, arch_mod} <- [
          {"PaddedUnion", PaddedUnion},
          {"TypedFrames", TypedFrames},
          {"PerTypeGroups", PerTypeGroups}
        ] do
      @arch_mod arch_mod

      test "#{arch_name}: single small entry" do
        entry = make_small(99)
        {:ok, binary} = @arch_mod.encode([entry], @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)
        assert @arch_mod.count(batch) == 1

        {:ok, {0, 0, decoded}} = @arch_mod.get(batch, 0)
        assert entries_equal?(entry, decoded)
      end

      test "#{arch_name}: single medium entry" do
        entry = make_medium(99)
        {:ok, binary} = @arch_mod.encode([entry], @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)
        [{0, 1, decoded}] = @arch_mod.to_list(batch)
        assert entries_equal?(entry, decoded)
      end

      test "#{arch_name}: single large entry" do
        entry = make_large(99)
        {:ok, binary} = @arch_mod.encode([entry], @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)
        [{0, 2, decoded}] = @arch_mod.to_list(batch)
        assert entries_equal?(entry, decoded)
      end

      test "#{arch_name}: heterogeneous 9 entries" do
        entries = [
          make_large(1),
          make_medium(2),
          make_small(3),
          make_large(4),
          make_small(5),
          make_medium(6),
          make_large(7),
          make_medium(8),
          make_small(9)
        ]

        {:ok, binary} = @arch_mod.encode(entries, @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)
        assert @arch_mod.count(batch) == 9

        result = @arch_mod.to_list(batch)
        assert length(result) == 9

        Enum.zip(entries, result)
        |> Enum.each(fn {original, {seq, tag, decoded}} ->
          assert seq == Enum.find_index(entries, &(&1 == original))
          assert tag == expected_tag(original)
          assert entries_equal?(original, decoded)
        end)
      end

      test "#{arch_name}: all same type" do
        entries = Enum.map(1..10, &make_large/1)
        {:ok, binary} = @arch_mod.encode(entries, @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)
        assert @arch_mod.count(batch) == 10

        result = @arch_mod.to_list(batch)

        Enum.zip(entries, result)
        |> Enum.each(fn {original, {_seq, tag, decoded}} ->
          assert tag == 2
          assert entries_equal?(original, decoded)
        end)
      end

      test "#{arch_name}: empty batch" do
        {:ok, binary} = @arch_mod.encode([], @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)
        assert @arch_mod.count(batch) == 0
        assert @arch_mod.to_list(batch) == []
      end
    end
  end

  # ----------------------------------------------------------------
  # Ordering — insertion order must be preserved
  # ----------------------------------------------------------------

  describe "ordering" do
    for {arch_name, arch_mod} <- [
          {"PaddedUnion", PaddedUnion},
          {"TypedFrames", TypedFrames},
          {"PerTypeGroups", PerTypeGroups}
        ] do
      @arch_mod arch_mod

      test "#{arch_name}: to_list preserves insertion order" do
        entries = mixed_entries(30)
        {:ok, binary} = @arch_mod.encode(entries, @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)

        result = @arch_mod.to_list(batch)
        seqs = Enum.map(result, fn {seq, _, _} -> seq end)
        assert seqs == Enum.to_list(0..29)
      end

      test "#{arch_name}: stream preserves insertion order" do
        entries = mixed_entries(30)
        {:ok, binary} = @arch_mod.encode(entries, @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)

        seqs =
          batch
          |> @arch_mod.stream()
          |> Enum.map(fn {seq, _, _} -> seq end)

        assert seqs == Enum.to_list(0..29)
      end

      test "#{arch_name}: stream take(5) is lazy and correct" do
        entries = mixed_entries(100)
        {:ok, binary} = @arch_mod.encode(entries, @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)

        first_5 =
          batch
          |> @arch_mod.stream()
          |> Enum.take(5)

        assert length(first_5) == 5
        seqs = Enum.map(first_5, fn {seq, _, _} -> seq end)
        assert seqs == [0, 1, 2, 3, 4]
      end
    end
  end

  # ----------------------------------------------------------------
  # Random access — get/2
  # ----------------------------------------------------------------

  describe "random access" do
    for {arch_name, arch_mod} <- [
          {"PaddedUnion", PaddedUnion},
          {"TypedFrames", TypedFrames},
          {"PerTypeGroups", PerTypeGroups}
        ] do
      @arch_mod arch_mod

      test "#{arch_name}: get first, middle, last" do
        entries = mixed_entries(20)
        {:ok, binary} = @arch_mod.encode(entries, @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)

        {:ok, {0, tag0, dec0}} = @arch_mod.get(batch, 0)
        assert tag0 == expected_tag(Enum.at(entries, 0))
        assert entries_equal?(Enum.at(entries, 0), dec0)

        {:ok, {10, tag10, dec10}} = @arch_mod.get(batch, 10)
        assert tag10 == expected_tag(Enum.at(entries, 10))
        assert entries_equal?(Enum.at(entries, 10), dec10)

        {:ok, {19, tag19, dec19}} = @arch_mod.get(batch, 19)
        assert tag19 == expected_tag(Enum.at(entries, 19))
        assert entries_equal?(Enum.at(entries, 19), dec19)
      end

      test "#{arch_name}: get out of bounds" do
        {:ok, binary} = @arch_mod.encode([make_small(1)], @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)
        assert {:error, _} = @arch_mod.get(batch, 1)
        assert {:error, _} = @arch_mod.get(batch, -1)
      end
    end
  end

  # ----------------------------------------------------------------
  # by_type filtering
  # ----------------------------------------------------------------

  describe "by_type" do
    for {arch_name, arch_mod} <- [
          {"PaddedUnion", PaddedUnion},
          {"TypedFrames", TypedFrames},
          {"PerTypeGroups", PerTypeGroups}
        ] do
      @arch_mod arch_mod

      test "#{arch_name}: filters correct entries" do
        entries = mixed_entries(30)
        {:ok, binary} = @arch_mod.encode(entries, @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)

        smalls = @arch_mod.by_type(batch, 0)
        mediums = @arch_mod.by_type(batch, 1)
        larges = @arch_mod.by_type(batch, 2)

        expected_smalls = entries |> Enum.filter(&match?(%SmallCommand{}, &1))
        expected_mediums = entries |> Enum.filter(&match?(%MediumCommand{}, &1))
        expected_larges = entries |> Enum.filter(&match?(%LargeCommand{}, &1))

        assert length(smalls) == length(expected_smalls)
        assert length(mediums) == length(expected_mediums)
        assert length(larges) == length(expected_larges)

        Enum.zip(expected_smalls, smalls)
        |> Enum.each(fn {orig, dec} -> assert entries_equal?(orig, dec) end)

        Enum.zip(expected_mediums, mediums)
        |> Enum.each(fn {orig, dec} -> assert entries_equal?(orig, dec) end)

        Enum.zip(expected_larges, larges)
        |> Enum.each(fn {orig, dec} -> assert entries_equal?(orig, dec) end)
      end

      test "#{arch_name}: by_type with no entries of that type" do
        entries = Enum.map(1..5, &make_large/1)
        {:ok, binary} = @arch_mod.encode(entries, @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)

        assert @arch_mod.by_type(batch, 0) == []
        assert @arch_mod.by_type(batch, 1) == []
        assert length(@arch_mod.by_type(batch, 2)) == 5
      end
    end
  end

  # ----------------------------------------------------------------
  # Count
  # ----------------------------------------------------------------

  describe "count" do
    for {arch_name, arch_mod} <- [
          {"PaddedUnion", PaddedUnion},
          {"TypedFrames", TypedFrames},
          {"PerTypeGroups", PerTypeGroups}
        ] do
      @arch_mod arch_mod

      for n <- [0, 1, 10, 100, 1000] do
        @n n

        test "#{arch_name}: count is #{n}" do
          entries = mixed_entries(@n)
          {:ok, binary} = @arch_mod.encode(entries, @type_specs)
          {:ok, batch} = @arch_mod.decode(binary, @type_specs)
          assert @arch_mod.count(batch) == @n
        end
      end
    end
  end

  # ----------------------------------------------------------------
  # Validation — reject unknown types
  # ----------------------------------------------------------------

  describe "validation" do
    for {arch_name, arch_mod} <- [
          {"PaddedUnion", PaddedUnion},
          {"TypedFrames", TypedFrames},
          {"PerTypeGroups", PerTypeGroups}
        ] do
      @arch_mod arch_mod

      test "#{arch_name}: rejects unknown struct types" do
        bogus = %GridCodec.TestSupport.OrderEvent{
          order_id: <<0::128>>,
          side: :buy,
          status: :open,
          price: 100,
          quantity: 10,
          timestamp: 0
        }

        assert_raise ArgumentError, ~r/not in any_of/, fn ->
          @arch_mod.encode([bogus], @type_specs)
        end
      end
    end
  end

  # ----------------------------------------------------------------
  # Wire size comparison
  # ----------------------------------------------------------------

  describe "wire size" do
    test "reports wire sizes for comparison" do
      for n <- [50, 500, 2000] do
        entries = mixed_entries(n)

        {:ok, bin_a} = PaddedUnion.encode(entries, @type_specs)
        {:ok, bin_b} = TypedFrames.encode(entries, @type_specs)
        {:ok, bin_c} = PerTypeGroups.encode(entries, @type_specs)

        assert PaddedUnion.wire_size(bin_a) > 0
        assert TypedFrames.wire_size(bin_b) > 0
        assert PerTypeGroups.wire_size(bin_c) > 0

        # PerTypeGroups should have the smallest wire size (4 bytes overhead per entry)
        # TypedFrames has 7 bytes overhead per entry
        # PaddedUnion has 5 bytes overhead + padding
        assert PerTypeGroups.wire_size(bin_c) <= TypedFrames.wire_size(bin_b)
      end
    end
  end

  # ----------------------------------------------------------------
  # Larger batches
  # ----------------------------------------------------------------

  describe "larger batches" do
    for {arch_name, arch_mod} <- [
          {"PaddedUnion", PaddedUnion},
          {"TypedFrames", TypedFrames},
          {"PerTypeGroups", PerTypeGroups}
        ] do
      @arch_mod arch_mod

      @tag :slow
      test "#{arch_name}: 8189 entries roundtrip" do
        entries = mixed_entries(8189)
        {:ok, binary} = @arch_mod.encode(entries, @type_specs)
        {:ok, batch} = @arch_mod.decode(binary, @type_specs)
        assert @arch_mod.count(batch) == 8189

        result = @arch_mod.to_list(batch)
        assert length(result) == 8189

        seqs = Enum.map(result, fn {seq, _, _} -> seq end)
        assert seqs == Enum.to_list(0..8188)
      end
    end
  end
end
