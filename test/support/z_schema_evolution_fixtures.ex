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
