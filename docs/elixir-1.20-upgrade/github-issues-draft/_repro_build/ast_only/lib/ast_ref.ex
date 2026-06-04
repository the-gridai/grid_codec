defmodule AstOnly.AstRef do
  # Macro.var(:name, nil) produces {name, meta, nil} — see reproduction 1
  def ref_kind({name, _meta, nil}) when is_atom(name), do: {:local_var, name}

  def ref_kind({name, _meta, context}) when is_atom(name) and is_atom(context),
    do: {:namespaced_var, name, context}

  def ref_kind(other), do: {:other, other}
end
