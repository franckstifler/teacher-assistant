defmodule TeacherAssistant.Accounts.Checks.NotCreatedByUnverifiedSchool do
  @moduledoc """
  Policy check for `:reset_temporary_password` and `:rename_by_school`: the school
  the actor acts in is not verified yet, and the account being changed is not one
  it created.

  Anyone can register and open a school, and a head links an existing phone
  account just by typing its number. Until an operator has verified the school,
  its head must not be able to reset — and so take over — or rename an account
  that someone else owns.
  """
  use Ash.Policy.SimpleCheck

  alias TeacherAssistant.Accounts.Checks.{SchoolRole, SchoolVerified}

  @impl true
  def describe(_opts), do: "the account was not created by the acting school, which is unverified"

  @impl true
  def match?(_actor, %{subject: %{data: %{id: id} = target} = subject}, _opts)
      when is_binary(id) do
    workspace_id = SchoolRole.workspace_id(subject)

    target.created_in_workspace_id != workspace_id and
      not SchoolVerified.verified?(workspace_id)
  end

  def match?(_actor, _context, _opts), do: false
end
