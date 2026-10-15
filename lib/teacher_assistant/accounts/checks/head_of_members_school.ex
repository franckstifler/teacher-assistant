defmodule TeacherAssistant.Accounts.Checks.HeadOfMembersSchool do
  @moduledoc """
  Policy check: the actor is an active head of the school they act in (the changeset's
  tenant), and the account being changed is an active member of that school
  (operator console spec §3).
  """
  use Ash.Policy.SimpleCheck

  alias TeacherAssistant.Accounts.Checks.SchoolRole

  @impl true
  def describe(_opts), do: "actor heads the acting school and the account is its member"

  @impl true
  def match?(actor, %{subject: %{data: %{id: id} = target} = subject}, _opts)
      when is_binary(id) do
    workspace_id = SchoolRole.workspace_id(subject)

    SchoolRole.holds?(actor, workspace_id, :head) and
      SchoolRole.holds?(target, workspace_id, :member)
  end

  def match?(_actor, _context, _opts), do: false
end
