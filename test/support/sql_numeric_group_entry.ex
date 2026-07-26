defmodule GridCodec.TestSupport.SQLNumericGroupEntry do
  @moduledoc false

  use GridCodec.Struct, template_id: 624, schema_id: 62, name: "SQLNumericGroupEntry"

  alias GridCodec.TestSupport.SQLWideStatus

  defcodec do
    field :status, SQLWideStatus
    field :amount, {:decimal, scale: 2}, wire_format: :i64
    field :positive_amount, {:positive_decimal, scale: 2}, wire_format: :u64
  end
end
