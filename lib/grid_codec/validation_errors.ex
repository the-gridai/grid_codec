defmodule GridCodec.ValidationErrors do
  @moduledoc """
  Container for multiple validation failures.

  GridCodec uses this when a validation pipeline accumulates more than one error
  for a struct or binary. The `errors` list contains individual
  `GridCodec.ValidationError` entries in declaration order.
  """

  defexception [:errors]

  @type t :: %__MODULE__{
          errors: [GridCodec.ValidationError.t()]
        }

  @impl true
  def message(%__MODULE__{errors: errors}) do
    count = length(errors)
    suffix = if count == 1, do: "", else: "s"
    messages = Enum.map_join(errors, "; ", &Exception.message/1)
    "#{count} validation failure#{suffix}: #{messages}"
  end
end
