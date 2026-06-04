defmodule NilAtomRepro1 do
  def normalize_ref(ast) do
    case ast do
      {name, _meta, context} when is_atom(name) and is_atom(context) -> name
      {name, _meta, nil} when is_atom(name) -> name
      other -> other
    end
  end
end
