defmodule GridCodec.Breaking.Issue do
  @moduledoc """
  A single breaking change issue detected by the checker.
  """

  @type category :: :wire | :source

  @type t :: %__MODULE__{
          rule: atom(),
          category: category(),
          message: String.t(),
          path: String.t(),
          location: map()
        }

  defstruct [:rule, :category, :message, :path, :location]

  @doc "Returns true if the issue is in the WIRE category."
  def wire?(%__MODULE__{category: :wire}), do: true
  def wire?(%__MODULE__{}), do: false

  @doc "Returns a formatted single-line string for terminal output."
  def format(%__MODULE__{} = issue) do
    rule_str = issue.rule |> Atom.to_string() |> String.pad_trailing(32)
    loc = format_location(issue.location)
    "  #{rule_str} #{loc} - #{issue.message}"
  end

  defp format_location(%{struct: s, field: f}), do: "#{s}.#{f}"
  defp format_location(%{struct: s, group: g, field: f}), do: "#{s}.#{g}.#{f}"
  defp format_location(%{struct: s, group: g}), do: "#{s}.#{g}"
  defp format_location(%{struct: s, batch: b}), do: "#{s}.#{b}"
  defp format_location(%{struct: s}), do: "#{s}"
  defp format_location(%{enum: e, value: v}), do: "#{e}.#{v}"
  defp format_location(%{enum: e}), do: "#{e}"
  defp format_location(%{type: t}), do: "#{t}"
  defp format_location(%{schema: s}), do: "schema(#{s})"
  defp format_location(_), do: ""
end
