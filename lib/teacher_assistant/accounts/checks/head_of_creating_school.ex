defmodule TeacherAssistant.Accounts.Checks.HeadOfCreatingSchool do
  @moduledoc """
  Policy check for the school-managed account actions: the actor is an active
  head (`:head` axis) of the school recorded in `created_in_workspace_id` —
  the value being written on create, the stored value on update — and that
  school is the one the actor is currently acting in (the changeset's tenant).
  A linked account created by another school, or one managed from a different
  school the actor also heads, therefore never matches.
  """
  use Ash.Policy.SimpleCheck

  alias TeacherAssistant.Accounts.Checks.SchoolRole

  @impl true
  def describe(_opts), do: "actor is a head of the school that created the account"

  @impl true
  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    workspace_id = Ash.Changeset.get_attribute(changeset, :created_in_workspace_id)

    SchoolRole.workspace_id(changeset) == workspace_id and
      SchoolRole.holds?(actor, workspace_id, :head)
  end

  def match?(_actor, _context, _opts), do: false
end
