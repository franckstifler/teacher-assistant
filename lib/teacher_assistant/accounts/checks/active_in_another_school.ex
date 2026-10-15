defmodule TeacherAssistant.Accounts.Checks.ActiveInAnotherSchool do
  @moduledoc """
  Policy check for `:reset_temporary_password`: the account being changed holds an
  **active** membership in a school other than the one the actor is acting in (the
  changeset's tenant). Such a person is also someone else's colleague, so this school
  must not take the account over by resetting its password (decided by the user,
  2026-10-07; the reference became the acting school with the operator console,
  2026-10-15, once heads could reset invited members too).

  Memberships are attribute-multitenant (`global? true`): the read below runs
  deliberately without a tenant, across every school.
  """
  use Ash.Policy.SimpleCheck

  alias TeacherAssistant.Accounts.Checks.SchoolRole
  alias TeacherAssistant.Accounts.SchoolMembership

  @impl true
  def describe(_opts), do: "the account is active in a school other than the acting one"

  @impl true
  def match?(_actor, %{subject: %{data: %{id: user_id}} = subject}, _opts)
      when is_binary(user_id) do
    acting_id = SchoolRole.workspace_id(subject)

    # Check-internal read: `authorize?: false` because a policy check must not
    # recurse into the policies it is part of; no tenant on purpose.
    SchoolMembership
    |> Ash.Query.for_read(:active_for_user, %{user_id: user_id})
    |> Ash.read!(authorize?: false)
    |> Enum.any?(&(&1.workspace_id != acting_id))
  end

  def match?(_actor, _context, _opts), do: false
end
