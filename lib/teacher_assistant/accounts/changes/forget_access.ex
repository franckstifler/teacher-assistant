defmodule TeacherAssistant.Accounts.Changes.ForgetAccess do
  @moduledoc """
  After a write that changes what a policy check reads, forgets the cached answer
  (`Accounts.AccessCache`): `kind: :member` for a `SchoolMembership` (the user's roles
  in that school), `kind: :school` for a `SchoolProfile` (whether it is verified).
  """
  use Ash.Resource.Change

  alias TeacherAssistant.Accounts.AccessCache

  @impl true
  def change(changeset, opts, _context) do
    kind = Keyword.fetch!(opts, :kind)

    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      forget(kind, record)
      {:ok, record}
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  defp forget(:member, record), do: AccessCache.forget_member(record.user_id, record.workspace_id)
  defp forget(:school, record), do: AccessCache.forget_school(record.workspace_id)
end
