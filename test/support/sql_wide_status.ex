defmodule GridCodec.TestSupport.SQLWideStatus do
  @moduledoc false

  use GridCodec.Types.Enum, encoding: :u16

  defenum do
    value(:pending, 1)
    value(:review, 300)
  end
end
