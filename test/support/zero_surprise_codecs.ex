# credo:disable-for-this-file Credo.Check.Readability.ModuleDoc

defmodule GridCodec.ZSEdge.TestEnum do
  use GridCodec.Types.Enum, encoding: :u8

  defenum do
    value(:buy, 0)
    value(:sell, 1)
    value(:cancel, 2)
  end
end

defmodule GridCodec.ZSEdge.TestBitset do
  use GridCodec.Types.Bitset, size: :u8

  flag(:admin, 0)
  flag(:moderator, 1)
  flag(:verified, 2)
  flag(:banned, 3)
end

defmodule GridCodec.ZSEdge.CharArray8 do
  use GridCodec.Types.CharArray, length: 8
end

# Codec modules — use the custom types above.

defmodule GridCodec.ZSEdge.EnumCodec do
  use GridCodec.Struct, template_id: 5020

  defcodec do
    field :side, GridCodec.ZSEdge.TestEnum
  end
end

defmodule GridCodec.ZSEdge.BitsetCodec do
  use GridCodec.Struct, template_id: 5021

  defcodec do
    field :flags, GridCodec.ZSEdge.TestBitset
  end
end

defmodule GridCodec.ZSEdge.CharCodec do
  use GridCodec.Struct, template_id: 5022

  defcodec do
    field :ticker, GridCodec.ZSEdge.CharArray8
  end
end

defmodule GridCodec.ZSEdge.AllNilCodec do
  use GridCodec.Struct, template_id: 5025

  defcodec do
    field :u, :u64
    field :i, :i64
    field :b, :bool
    field :uuid, :uuid_string
    field :ts, :timestamp_us
    field :dt, :datetime_us
    field :dec, :decimal
    field :flags, GridCodec.ZSEdge.TestBitset
    field :ticker, GridCodec.ZSEdge.CharArray8
    field :side, GridCodec.ZSEdge.TestEnum
  end
end

defmodule GridCodec.ZSEdge.StringCodec do
  use GridCodec.Struct, template_id: 5028

  defcodec do
    field :s16, :string16
  end
end

defmodule GridCodec.ZSEdge.IntegerCodec do
  use GridCodec.Struct, template_id: 5029, validate: true

  defcodec do
    field :u8, :u8
    field :u32, :u32
    field :i8, :i8
    field :i64, :i64
  end
end

defmodule GridCodec.ZSEdge.PosdecCodec do
  use GridCodec.Struct, template_id: 5026

  defcodec do
    field :val, :positive_decimal
  end
end

defmodule GridCodec.ZSEdge.F64Codec do
  use GridCodec.Struct, template_id: 5027

  defcodec do
    field :f, :f64
  end
end
