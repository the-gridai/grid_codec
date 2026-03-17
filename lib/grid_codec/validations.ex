defmodule GridCodec.Validations do
  @moduledoc """
  Helpers for struct-level validation pipelines.

  This module provides a small set of builtin validator descriptors that
  `GridCodec.Struct` can compile into decoded and binary validation paths.
  Function validators remain available for rich, decoded-only logic.
  """

  alias GridCodec.ValidationError

  @type validator ::
          %{
            required(:kind) => :compare | :present | :one_of | :expr,
            required(:supports) => [atom()],
            optional(:field) => atom(),
            optional(:lhs) => atom(),
            optional(:op) => atom(),
            optional(:rhs) => atom() | term(),
            optional(:allowed) => [term()],
            optional(:expr) => Macro.t(),
            optional(:allow_nil?) => boolean()
          }

  @type callback_result ::
          :ok
          | ValidationError.t()
          | [ValidationError.t()]
          | {:error, ValidationError.t() | [ValidationError.t()] | term()}

  @compare_ops [:==, :!=, :>, :>=, :<, :<=]

  @spec compare(atom(), atom(), atom() | term(), keyword()) :: validator()
  def compare(field, op, rhs, opts \\ [])
      when is_atom(field) and op in @compare_ops do
    %{
      kind: :compare,
      lhs: field,
      op: op,
      rhs: rhs,
      allow_nil?: Keyword.get(opts, :allow_nil?, true),
      supports: [:decoded, :binary]
    }
  end

  @spec present(atom()) :: validator()
  def present(field) when is_atom(field) do
    %{kind: :present, field: field, supports: [:decoded, :binary]}
  end

  @spec one_of(atom(), [term()], keyword()) :: validator()
  def one_of(field, allowed, opts \\ []) when is_atom(field) and is_list(allowed) do
    %{
      kind: :one_of,
      field: field,
      allowed: allowed,
      allow_nil?: Keyword.get(opts, :allow_nil?, true),
      supports: [:decoded, :binary]
    }
  end

  @doc false
  @spec expr(Macro.t()) :: validator()
  def expr(ast) do
    %{kind: :expr, expr: ast, supports: [:decoded]}
  end

  @doc false
  @spec normalize_callback_result(module(), atom(), atom(), callback_result()) ::
          [ValidationError.t()]
  def normalize_callback_result(module, name, category, result) do
    case result do
      :ok ->
        []

      [] ->
        []

      %ValidationError{} = error ->
        [error]

      [%ValidationError{} | _] = errors ->
        errors

      {:error, %ValidationError{} = error} ->
        [error]

      {:error, [%ValidationError{} | _] = errors} ->
        errors

      {:error, reason} ->
        [ValidationError.invariant_failed(module, name, inspect(reason), %{category: category})]

      other ->
        [ValidationError.invariant_failed(module, name, inspect(other), %{category: category})]
    end
  end

  @doc false
  @spec compare_terms(term(), atom(), term()) :: boolean()
  def compare_terms(left, :==, right), do: left == right
  def compare_terms(left, :!=, right), do: left != right
  def compare_terms(left, :>, right), do: left > right
  def compare_terms(left, :>=, right), do: left >= right
  def compare_terms(left, :<, right), do: left < right
  def compare_terms(left, :<=, right), do: left <= right
end
