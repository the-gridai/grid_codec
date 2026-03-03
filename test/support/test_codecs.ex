defmodule GridCodec.TestSupport.OrderEvent do
  @moduledoc false
  use GridCodec.Struct, template_id: 600, schema_id: 60, name: "OrderEvent"

  alias GridCodec.TestSupport.Side
  alias GridCodec.TestSupport.Status

  defcodec do
    field :order_id, :uuid
    field :side, Side
    field :status, Status
    field :price, :u64
    field :quantity, :u32
    field :timestamp, :timestamp_us
  end
end

defmodule GridCodec.TestSupport.OrderEventNoTypespec do
  @moduledoc false
  use GridCodec.Struct,
    template_id: 601,
    schema_id: 60,
    name: "OrderEventNoTypespec",
    generate_typespec: false

  defcodec do
    field :order_id, :uuid
    field :price, :u64
  end
end

defmodule GridCodec.TestSupport.OrderEventVar do
  @moduledoc false
  use GridCodec.Struct, template_id: 602, schema_id: 60, name: "OrderEventVar"

  defcodec do
    field :order_id, :uuid
    field :symbol, :string16
  end
end

defmodule GridCodec.TestSupport.RequiredTypesStruct do
  @moduledoc false
  use GridCodec.Struct, template_id: 603, schema_id: 60

  defcodec do
    field :id, :uuid, presence: :required
    field :price, :u64, presence: :required
    field :quantity, :u32
  end
end

defmodule GridCodec.TestSupport.ConstantTypesStruct do
  @moduledoc false
  use GridCodec.Struct, template_id: 604, schema_id: 60

  defcodec do
    field :id, :u64
    field :version, :u8, presence: :constant, value: 1
  end
end
