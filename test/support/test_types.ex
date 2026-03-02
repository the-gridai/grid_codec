defmodule GridCodec.TestSupport.Side do
  @moduledoc false
  use GridCodec.Types.Enum, encoding: :u8

  defenum do
    value(:buy)
    value(:sell)
  end
end

defmodule GridCodec.TestSupport.Status do
  @moduledoc false
  use GridCodec.Types.Enum, encoding: :u8

  defenum do
    value(:open)
    value(:filled)
    value(:cancelled)
  end
end
