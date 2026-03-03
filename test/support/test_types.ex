defmodule GridCodec.TestSupport.Side do
  @moduledoc false
  use GridCodec.Types.Enum, encoding: :u8

  defenum do
    value(:buy, 0)
    value(:sell, 1)
  end
end

defmodule GridCodec.TestSupport.Status do
  @moduledoc false
  use GridCodec.Types.Enum, encoding: :u8

  defenum do
    value(:open, 0)
    value(:filled, 1)
    value(:cancelled, 2)
  end
end
