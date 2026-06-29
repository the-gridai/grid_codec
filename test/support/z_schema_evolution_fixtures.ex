# credo:disable-for-this-file Credo.Check.Readability.ModuleDoc
#
# Shared schema-evolution codec fixtures (compiled via test/support so other
# test modules can reference them; test/*.exs nested modules are not always
# loaded before other async tests).

defmodule GridCodec.TestSupport.SchemaEvo.ReqSinceV1 do
  use GridCodec.Struct, template_id: 920, version: 1

  defcodec do
    field :id, :u64
    field :price, :u32
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.ReqSinceV2NoDefault do
  use GridCodec.Struct, template_id: 920, version: 2

  defcodec do
    field :id, :u64
    field :price, :u32
    field :qty, :u32, since: 2, presence: :required
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.ReqSinceAltV1 do
  use GridCodec.Struct, template_id: 921, version: 1

  defcodec do
    field :id, :u64
    field :price, :u32
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.ReqSinceAltV2WithDefault do
  use GridCodec.Struct, template_id: 921, version: 2

  defcodec do
    field :id, :u64
    field :price, :u32
    field :qty, :u32, since: 2, presence: :required, default: 0
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.DefaultsEvolV1 do
  use GridCodec.Struct, template_id: 940, version: 1

  defcodec do
    field :id, :u64
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.DefaultsEvolV2 do
  use GridCodec.Struct,
    template_id: 940,
    version: 2,
    field_defaults: [presence: :required, default: 0]

  defcodec do
    field :id, :u64
    field :score, :u32, since: 2
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.GroupPadWriterV1 do
  use GridCodec.Struct, template_id: 930, version: 1

  defcodec do
    field :id, :u64

    group :items do
      field :qty, :u32
    end
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.GroupPadReqReaderV2 do
  use GridCodec.Struct, template_id: 930, version: 2

  defcodec do
    field :id, :u64
    field :seq, :u32, since: 2

    group :items do
      field :qty, :u32, presence: :required
    end
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.GroupPadWriterAltV1 do
  use GridCodec.Struct, template_id: 931, version: 1

  defcodec do
    field :id, :u64

    group :items do
      field :qty, :u32
    end
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.GroupPadReqDefaultV2 do
  use GridCodec.Struct, template_id: 931, version: 2

  defcodec do
    field :id, :u64
    field :seq, :u32, since: 2

    group :items do
      field :qty, :u32, presence: :required, default: 0
    end
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.EvolutionTinyCmd do
  use GridCodec.Struct, template_id: 923, version: 1

  defcodec do
    field :cmd_id, :u64
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.BatchParentV1 do
  use GridCodec.Struct, template_id: 924, version: 1

  defcodec do
    field :market_id, :uuid

    batch(:commands,
      any_of: [GridCodec.TestSupport.SchemaEvo.EvolutionTinyCmd],
      strategy: :typed_frames
    )
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.BatchParentV2 do
  use GridCodec.Struct, template_id: 924, version: 2

  defcodec do
    field :market_id, :uuid
    field :trace_id, :u64, since: 2

    batch(:commands,
      any_of: [GridCodec.TestSupport.SchemaEvo.EvolutionTinyCmd],
      strategy: :typed_frames
    )
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.ConstAppendV1 do
  use GridCodec.Struct, template_id: 925, version: 1

  defcodec do
    field :id, :u64
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.ConstAppendV2 do
  use GridCodec.Struct, template_id: 925, version: 2

  defcodec do
    field :id, :u64
    field :lane, :u8, since: 2, presence: :constant, value: 3
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.DecWfV1 do
  use GridCodec.Struct, template_id: 926, version: 1

  defcodec do
    field :id, :u64
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.DecWfV2 do
  use GridCodec.Struct, template_id: 926, version: 2

  defcodec do
    field :id, :u64

    field :amount, {:decimal, scale: 8},
      wire_format: :i64,
      since: 2
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.DecWfReqDefV1 do
  use GridCodec.Struct, template_id: 927, version: 1

  defcodec do
    field :id, :u64
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.DecWfReqDefV2 do
  use GridCodec.Struct, template_id: 927, version: 2

  defcodec do
    field :id, :u64

    field :amount, {:decimal, scale: 8},
      wire_format: :i64,
      since: 2,
      presence: :required,
      default: Decimal.new("0")
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.EnumEvolV1 do
  use GridCodec.Struct, template_id: 928, version: 1

  defcodec do
    field :id, :u64
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.EnumEvolV2 do
  use GridCodec.Struct, template_id: 928, version: 2

  defcodec do
    field :id, :u64
    field :side, GridCodec.ZSEdge.TestEnum, since: 2
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.BatchPaddedTiny do
  use GridCodec.Struct, template_id: 1980, version: 1

  defcodec do
    field :x, :u64
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.BatchPaddedWide do
  use GridCodec.Struct, template_id: 1981, version: 1

  defcodec do
    field :a, :u64
    field :b, :u64
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.BatchPaddedParentV1 do
  use GridCodec.Struct, template_id: 1982, version: 1

  defcodec do
    field :sid, :u32

    batch(:cmds,
      any_of: [
        GridCodec.TestSupport.SchemaEvo.BatchPaddedTiny,
        GridCodec.TestSupport.SchemaEvo.BatchPaddedWide
      ]
    )
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.BatchPaddedParentV2 do
  use GridCodec.Struct, template_id: 1982, version: 2

  defcodec do
    field :sid, :u32
    field :epoch, :u16, since: 2

    batch(:cmds,
      any_of: [
        GridCodec.TestSupport.SchemaEvo.BatchPaddedTiny,
        GridCodec.TestSupport.SchemaEvo.BatchPaddedWide
      ]
    )
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.ScalarScoresV1 do
  use GridCodec.Struct, template_id: 1983, version: 1

  defcodec do
    field :owner, :u64

    group :scores, of: :u32
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.ScalarScoresV2 do
  use GridCodec.Struct, template_id: 1983, version: 2

  defcodec do
    field :owner, :u64
    field :version_tag, :u8, since: 2

    group :scores, of: :u32
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.VarAppendBaseV1 do
  use GridCodec.Struct, template_id: 1984, version: 1

  defcodec do
    field :id, :u64
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.VarAppendStringV2 do
  use GridCodec.Struct, template_id: 1984, version: 2

  defcodec do
    field :id, :u64
    field :note, :string16, since: 2, presence: :optional
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.VarAppendExistingV1 do
  use GridCodec.Struct, template_id: 1985, version: 1

  defcodec do
    field :id, :u64
    field :name, :string16
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.VarAppendExistingV2 do
  use GridCodec.Struct, template_id: 1985, version: 2

  defcodec do
    field :id, :u64
    field :name, :string16
    field :note, :string16, since: 2, presence: :optional
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.VarBeforeFixedV1 do
  use GridCodec.Struct, template_id: 1986, version: 1

  defcodec do
    field :id, :u64
    field :some_string, :string16, presence: :required
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.VarBeforeFixedV2 do
  use GridCodec.Struct, template_id: 1986, version: 2

  defcodec do
    field :id, :u64
    field :some_string, :string16, presence: :required
    field :extra, :i64, since: 2, presence: :optional
  end
end

# Regression fixtures for the appended-group short-binary guard
# (`GridCodec.Group.parse_with_rest!/3`). v1 has no group; v2 appends a typed
# `since: 2` group. A historical v1 payload has an empty tail where the group
# header is expected, which must raise a CATCHABLE ArgumentError (so consumers
# can synthesize an empty group / pad) rather than an uncatchable
# FunctionClauseError.
defmodule GridCodec.TestSupport.SchemaEvo.AppendedGroupEntry do
  use GridCodec.Struct, template_id: 1988, version: 1

  defcodec do
    field :a, :u32
    field :b, :u32
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.AppendedGroupV1 do
  use GridCodec.Struct, template_id: 1987, version: 1

  defcodec do
    field :id, :u64
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.AppendedGroupV2 do
  use GridCodec.Struct, template_id: 1987, version: 2

  defcodec do
    field :id, :u64
    group :queue, of: GridCodec.TestSupport.SchemaEvo.AppendedGroupEntry, since: 2
  end
end

# ============================================================================
# Version-aware fixed group ENTRY evolution fixtures.
#
# These prove that appending an optional/defaulted field to a struct used as a
# fixed group entry (`group :g, of: Module`) or to an inline group
# (`group :g do ... end`) is a safe, additive change. Older group bytes (shorter
# entries) decode under the newer reader with the appended field defaulted.
# ============================================================================

# --- Typed group entry: optional append ---
defmodule GridCodec.TestSupport.SchemaEvo.OrderEntryV1 do
  use GridCodec.Struct, template_id: 1990, version: 1

  defcodec do
    field :price, :u64
    field :qty, :u32
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.OrderEntryV2 do
  use GridCodec.Struct, template_id: 1990, version: 2

  defcodec do
    field :price, :u64
    field :qty, :u32
    field :autotransfer, :bool, since: 2, presence: :optional, default: false
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.OrderBookV1 do
  use GridCodec.Struct, template_id: 1991, version: 1

  defcodec do
    field :market_id, :u64
    group :orders, of: GridCodec.TestSupport.SchemaEvo.OrderEntryV1
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.OrderBookV2 do
  use GridCodec.Struct, template_id: 1991, version: 2

  defcodec do
    field :market_id, :u64
    group :orders, of: GridCodec.TestSupport.SchemaEvo.OrderEntryV2
  end
end

# --- Typed group entry: required + default append ---
defmodule GridCodec.TestSupport.SchemaEvo.LotEntryV1 do
  use GridCodec.Struct, template_id: 1992, version: 1

  defcodec do
    field :sku, :u64
    field :count, :u32
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.LotEntryV2 do
  use GridCodec.Struct, template_id: 1992, version: 2

  defcodec do
    field :sku, :u64
    field :count, :u32
    field :grade, :u8, since: 2, presence: :required, default: 7
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.WarehouseV1 do
  use GridCodec.Struct, template_id: 1993, version: 1

  defcodec do
    field :wh_id, :u64
    group :lots, of: GridCodec.TestSupport.SchemaEvo.LotEntryV1
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.WarehouseV2 do
  use GridCodec.Struct, template_id: 1993, version: 2

  defcodec do
    field :wh_id, :u64
    group :lots, of: GridCodec.TestSupport.SchemaEvo.LotEntryV2
  end
end

# --- Typed group with lookups: optional+default append ---
# Used to lock in that generated group lookups project correctly over padded
# historical entries (an older writer's narrower group is decoded by the newer
# reader, padded up, then keyed/filtered).
defmodule GridCodec.TestSupport.SchemaEvo.LookupBookV1 do
  use GridCodec.Struct, template_id: 1996, schema_id: 199, version: 1

  defcodec do
    field :market_id, :u64
    group :orders, of: GridCodec.TestSupport.SchemaEvo.OrderEntryV1
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.LookupBookV2 do
  use GridCodec.Struct, template_id: 1996, schema_id: 199, version: 2

  defcodec do
    field :market_id, :u64
    group :orders, of: GridCodec.TestSupport.SchemaEvo.OrderEntryV2

    lookups do
      lookup :orders_by_price do
        from(:orders)
        into(:map)
        key(:price)
      end

      lookup :no_autotransfer do
        from(:orders)
        into(:list)
        where(autotransfer: false)
      end
    end
  end
end

# --- Inline group: optional append ---
defmodule GridCodec.TestSupport.SchemaEvo.InlineGroupV1 do
  use GridCodec.Struct, template_id: 1994, version: 1

  defcodec do
    field :id, :u64

    group :items do
      field :a, :u32
      field :b, :u16
    end
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.InlineGroupV2 do
  use GridCodec.Struct, template_id: 1994, version: 2

  defcodec do
    field :id, :u64

    group :items do
      field :a, :u32
      field :b, :u16
      field :c, :u32, since: 2, presence: :optional
    end
  end
end

# --- Inline group: required + default append ---
defmodule GridCodec.TestSupport.SchemaEvo.InlineGroupReqV1 do
  use GridCodec.Struct, template_id: 1995, version: 1

  defcodec do
    field :id, :u64

    group :items do
      field :a, :u32
    end
  end
end

defmodule GridCodec.TestSupport.SchemaEvo.InlineGroupReqV2 do
  use GridCodec.Struct, template_id: 1995, version: 2

  defcodec do
    field :id, :u64

    group :items do
      field :a, :u32
      field :flag, :u8, since: 2, presence: :required, default: 3
    end
  end
end
