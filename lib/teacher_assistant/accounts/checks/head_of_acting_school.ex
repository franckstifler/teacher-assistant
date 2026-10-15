defmodule TeacherAssistant.Accounts.Checks.HeadOfActingSchool do
  @moduledoc """
  Policy check: the account being changed holds the `:head` axis in the school the
  actor is acting in (the changeset's tenant). A head never resets another head
  (operator console spec §3).
  """
  use Ash.Policy.SimpleCheck

  alias TeacherAssistant.Accounts.Checks.SchoolRole

  @impl true
  def describe(_opts), do: "the account is a head of the acting school"

  @impl true
  def match?(_actor, %{subject: %{data: %{id: id} = target} = subject}, _opts)
      when is_binary(id),
      do: SchoolRole.holds?(target, SchoolRole.workspace_id(subject), :head)

  def match?(_actor, _context, _opts), do: false
end
