defmodule GridCodec.Breaking.Policy do
  @moduledoc """
  Applies severity policy to breaking-change issues.

  Existing wire and source compatibility issues default to `:error`. Documentation
  drift is reported by default without failing CI unless the project opts into a
  stricter policy.
  """

  alias GridCodec.Breaking.Issue

  @type severity :: Issue.severity()

  @default_doc_severities %{
    DOC_FIELD_DOC_ADDED: :info,
    DOC_FIELD_DOC_CHANGED: :warning,
    DOC_FIELD_DOC_REMOVED: :warning,
    DOC_GROUP_DOC_ADDED: :info,
    DOC_GROUP_DOC_CHANGED: :warning,
    DOC_GROUP_DOC_REMOVED: :warning,
    DOC_GROUP_FIELD_DOC_ADDED: :info,
    DOC_GROUP_FIELD_DOC_CHANGED: :warning,
    DOC_GROUP_FIELD_DOC_REMOVED: :warning,
    DOC_ENUM_VALUE_DOC_ADDED: :info,
    DOC_ENUM_VALUE_DOC_CHANGED: :warning,
    DOC_ENUM_VALUE_DOC_REMOVED: :warning
  }

  @doc """
  Returns the default severity for a rule.
  """
  @spec severity_for(atom(), Issue.category(), map()) :: severity()
  def severity_for(rule, category, overrides \\ %{}) do
    Map.get(overrides, rule) || default_severity(rule, category)
  end

  @doc """
  Attaches severities to issues using policy overrides.
  """
  @spec apply([Issue.t()], map()) :: [Issue.t()]
  def apply(issues, overrides \\ %{}) do
    Enum.map(issues, fn issue ->
      %{issue | severity: severity_for(issue.rule, issue.category, overrides)}
    end)
  end

  @doc """
  Returns `true` when an issue should fail the current check.
  """
  @spec blocking?(Issue.t(), [severity()]) :: boolean()
  def blocking?(%Issue{severity: severity}, fail_on) when is_list(fail_on) do
    severity in fail_on
  end

  defp default_severity(rule, :docs), do: Map.get(@default_doc_severities, rule, :warning)
  defp default_severity(_rule, _category), do: :error
end
