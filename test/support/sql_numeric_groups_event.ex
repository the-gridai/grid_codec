defmodule GridCodec.TestSupport.SQLNumericGroupsEvent do
  @moduledoc false

  use GridCodec.Struct, template_id: 625, schema_id: 62, name: "SQLNumericGroupsEvent"

  alias GridCodec.TestSupport.SQLNumericGroupEntry
  alias GridCodec.TestSupport.SQLWideStatus

  defcodec do
    field :event_id, :u64

    group :inline_values do
      field :status, SQLWideStatus
      field :amount, {:decimal, scale: 2}, wire_format: :i64
      field :positive_amount, {:positive_decimal, scale: 2}, wire_format: :u64
    end

    group :typed_values, of: SQLNumericGroupEntry
  end
end
