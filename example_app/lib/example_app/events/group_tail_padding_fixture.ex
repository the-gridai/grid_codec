defmodule ExampleApp.Events.GroupTailAllocation do
  @moduledoc false
  use GridCodec.Struct, template_id: 9921, schema_id: 100, version: 1

  defcodec do
    field :qty, :u32
  end
end

defmodule ExampleApp.Events.GroupTailPaddingV2 do
  @moduledoc """
  Reader for group-tail padding evolution (v2 adds optional `auto_transfer` before the group).

  Historical v1 payloads must decode via `Header.block_length` padding. See
  `ExampleApp.GroupTailPaddingTest` for consolidated `GridCodec.decode/1` coverage.
  """
  use GridCodec.Struct,
    template_id: 9920,
    schema_id: 100,
    version: 2,
    name: "GroupTailPadding",
    field_defaults: [presence: :optional, default: false]

  alias ExampleApp.Events.GroupTailAllocation

  defcodec do
    field :id, :u64
    field :auto_transfer, :bool, presence: :optional, since: 2, default: false

    group :allocations, of: GroupTailAllocation, framing: :length_prefixed
  end
end
