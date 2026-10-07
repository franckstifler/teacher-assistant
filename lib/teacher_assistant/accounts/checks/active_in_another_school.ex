defmodule TeacherAssistant.Accounts.Checks.ActiveInAnotherSchool do
  @moduledoc """
  Policy check for `:reset_temporary_password`: the account being changed holds
  an **active** membership in a school other than the one that created it
  (`created_in_workspace_id`). Such a person is also someone else's colleague,
  so the creating school must not be able to take the account over by
  resetting its password (decided by the user, 2026-10-07).

  Memberships are attribute-multitenant (`global? true`): the read below runs
  deliberately without a tenant, across every school.
  """
  use Ash.Policy.SimpleCheck

  alias TeacherAssistant.Accounts.SchoolMembership

  @impl true
  def describe(_opts), do: "the account is active in a school other than the one that created it"

  @impl true
  def match?(
        _actor,
        %{subject: %{data: %{id: user_id, created_in_workspace_id: creating_id}}},
        _opts
      )
      when is_binary(user_id) do
    # Check-internal read: `authorize?: false` because a policy check must not
    # recurse into the policies it is part of; no tenant on purpose.
    SchoolMembership
    |> Ash.Query.for_read(:active_for_user, %{user_id: user_id})
    |> Ash.read!(authorize?: false)
    |> Enum.any?(&(&1.workspace_id != creating_id))
  end

  def match?(_actor, _context, _opts), do: false
end
