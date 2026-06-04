defmodule Legit.AstRef do
  @doc "Classify Elixir AST reference nodes (see Macro.var/2, quote)."
  def ref_kind({name, _meta, nil}) when is_atom(name), do: {:local_var, name}
  def ref_kind({name, _meta, context}) when is_atom(name) and is_atom(context), do: {:var, name, context}
  def ref_kind(other), do: {:other, other}
end
