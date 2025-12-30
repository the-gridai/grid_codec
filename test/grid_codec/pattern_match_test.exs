# Define codecs outside the test module
defmodule GridCodec.PatternMatchTest.Message do
  use GridCodec

  defcodec do
    field :type, :u8
    field :id, :u64
    field :value, :u32
    field :active, :bool
  end
end

defmodule GridCodec.PatternMatchTest.WithUUID do
  use GridCodec

  defcodec do
    field :user_id, :uuid
    field :score, :u64
  end
end

defmodule GridCodec.PatternMatchTest do
  use ExUnit.Case, async: true

  alias __MODULE__.Message
  alias __MODULE__.WithUUID

  require Message
  require WithUUID

  describe "match/1 macro" do
    test "matches all fields" do
      binary = Message.encode(%{type: 1, id: 123, value: 456, active: true})

      assert Message.match(type: t, id: i, value: v, active: a) = binary
      assert t == 1
      assert i == 123
      assert v == 456
      assert a == 1
    end

    test "matches subset of fields" do
      binary = Message.encode(%{type: 2, id: 999, value: 100, active: false})

      assert Message.match(type: t, id: i) = binary
      assert t == 2
      assert i == 999
    end

    test "matches single field" do
      binary = Message.encode(%{type: 3, id: 500, value: 200, active: true})

      assert Message.match(type: t) = binary
      assert t == 3
    end

    test "matches with empty binding list" do
      binary = Message.encode(%{type: 1, id: 1, value: 1, active: true})

      # Should match any valid binary
      assert Message.match() = binary
    end

    test "works in case expression" do
      binary1 = Message.encode(%{type: 1, id: 100, value: 50, active: true})
      binary2 = Message.encode(%{type: 2, id: 200, value: 60, active: false})
      binary3 = Message.encode(%{type: 3, id: 300, value: 70, active: true})

      result1 =
        case binary1 do
          Message.match(type: 1, id: id) -> {:command, id}
          Message.match(type: 2, id: id) -> {:query, id}
          _ -> :unknown
        end

      result2 =
        case binary2 do
          Message.match(type: 1, id: id) -> {:command, id}
          Message.match(type: 2, id: id) -> {:query, id}
          _ -> :unknown
        end

      result3 =
        case binary3 do
          Message.match(type: 1, id: id) -> {:command, id}
          Message.match(type: 2, id: id) -> {:query, id}
          _ -> :unknown
        end

      assert result1 == {:command, 100}
      assert result2 == {:query, 200}
      assert result3 == :unknown
    end

    test "works with guards" do
      low_score = Message.encode(%{type: 1, id: 1, value: 50, active: true})
      mid_score = Message.encode(%{type: 1, id: 2, value: 500, active: true})
      high_score = Message.encode(%{type: 1, id: 3, value: 5000, active: true})

      classify = fn binary ->
        case binary do
          Message.match(value: v) when v >= 1000 -> :expert
          Message.match(value: v) when v >= 100 -> :intermediate
          Message.match() -> :beginner
        end
      end

      assert classify.(low_score) == :beginner
      assert classify.(mid_score) == :intermediate
      assert classify.(high_score) == :expert
    end

    test "matches UUID fields as binary" do
      uuid = :crypto.strong_rand_bytes(16)
      binary = WithUUID.encode(%{user_id: uuid, score: 1000})

      assert WithUUID.match(user_id: uid, score: s) = binary
      assert uid == uuid
      assert s == 1000
    end

    test "doesn't match shorter binary" do
      binary = <<1, 2, 3>>

      result =
        case binary do
          Message.match(type: _) -> :matched
          _ -> :no_match
        end

      assert result == :no_match
    end

    test "matches binary with extra trailing data" do
      binary = Message.encode(%{type: 1, id: 123, value: 456, active: true})
      extended = <<binary::binary, "extra data">>

      assert Message.match(type: t, id: i) = extended
      assert t == 1
      assert i == 123
    end
  end

  describe "function clause pattern matching" do
    # Define a handler module that uses pattern matching in function heads
    defmodule Handler do
      require GridCodec.PatternMatchTest.Message, as: Msg

      def handle(Msg.match(type: 1, id: id)), do: {:command, id}
      def handle(Msg.match(type: 2, id: id)), do: {:query, id}
      def handle(Msg.match(type: t)), do: {:other, t}
    end

    test "works in function definition" do
      cmd = Message.encode(%{type: 1, id: 42, value: 0, active: true})
      qry = Message.encode(%{type: 2, id: 99, value: 0, active: true})
      oth = Message.encode(%{type: 5, id: 1, value: 0, active: true})

      assert Handler.handle(cmd) == {:command, 42}
      assert Handler.handle(qry) == {:query, 99}
      assert Handler.handle(oth) == {:other, 5}
    end
  end

  describe "match/1 error cases" do
    test "raises on unknown field at compile time" do
      # Test that the macro properly validates field names.
      # We test this by calling the internal function directly since Code.eval_quoted
      # with macros in pattern position hits Elixir's "remote function in match" check
      # before the macro can expand.
      field_info = [
        {:type, :u8, GridCodec.Types.Primitives.U8, 0, 1},
        {:id, :u64, GridCodec.Types.Primitives.U64, 1, 8}
      ]

      assert_raise ArgumentError, ~r/unknown or non-matchable fields: \[:unknown_field\]/, fn ->
        GridCodec.Compiler.__build_match_pattern__(
          [unknown_field: {:x, [], nil}],
          field_info,
          9,
          :little
        )
      end
    end
  end
end
