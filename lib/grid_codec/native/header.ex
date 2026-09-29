defmodule GridCodec.Native.Header do
  @moduledoc false

  @enforce_keys [:block_length, :template_id, :schema_id, :version]
  defstruct [:block_length, :template_id, :schema_id, :version]

  @type t :: %__MODULE__{
          block_length: non_neg_integer(),
          template_id: non_neg_integer(),
          schema_id: non_neg_integer(),
          version: non_neg_integer()
        }
end
