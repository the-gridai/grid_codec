defmodule GridCodec.TestSupport.SQLGroupSymbol do
  @moduledoc false

  use GridCodec.Types.CharArray, length: 8
end

defmodule GridCodec.TestSupport.SQLGroupEntry do
  @moduledoc false

  use GridCodec.Struct, template_id: 620, schema_id: 62, name: "SQLGroupEntry"

  alias GridCodec.TestSupport.SQLGroupSymbol

  defcodec do
    field :symbol, SQLGroupSymbol
    field :score, :i32
    field :related_id, :uuid_string
  end
end

defmodule GridCodec.TestSupport.SQLGroupsEvent do
  @moduledoc false

  use GridCodec.Struct, template_id: 621, schema_id: 62, name: "SQLGroupsEvent"

  alias GridCodec.TestSupport.SQLGroupEntry
  alias GridCodec.TestSupport.SQLGroupSymbol

  defcodec do
    field :event_id, :u64

    group :signals do
      field :symbol, SQLGroupSymbol
      field :score, :i32
      field :related_id, :uuid_string
    end

    group :history, of: SQLGroupEntry
    group :codes, of: :i32

    field :reason, :string16
    field :detail, :string16
  end
end
