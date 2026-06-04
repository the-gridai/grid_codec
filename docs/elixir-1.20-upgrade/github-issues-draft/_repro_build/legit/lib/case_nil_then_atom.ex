defmodule Legit.CaseNilThenAtom do
  def classify(value) do
    case value do
      nil -> :nil
      n when is_integer(n) -> {:int, n}
      a when is_atom(a) -> {:atom, a}
      b when is_binary(b) -> {:bin, b}
      _ -> :unknown
    end
  end
end
