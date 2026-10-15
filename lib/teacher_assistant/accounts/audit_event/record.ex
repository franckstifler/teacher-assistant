defmodule TeacherAssistant.Accounts.AuditEvent.Record do
  @moduledoc """
  Journals the action it is attached to (operator console spec §4), in the action's
  transaction: a failed journal write fails the action.

      change {TeacherAssistant.Accounts.AuditEvent.Record, action: :school_suspended}
  """
  use Ash.Resource.Change

  alias TeacherAssistant.Accounts.AuditEvent

  @impl true
  def change(changeset, opts, context) do
    action = Keyword.fetch!(opts, :action)
    before = changeset.data

    Ash.Changeset.after_action(changeset, fn changeset, record ->
      AuditEvent
      |> Ash.Changeset.for_create(:record, %{
        actor_user_id: context.actor && context.actor.id,
        action: action,
        workspace_id: workspace_id(record, changeset),
        target_user_id: target_user_id(changeset, record),
        details: details(action, before, record)
      })
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, _event} -> {:ok, record}
        {:error, error} -> {:error, error}
      end
    end)
  end

  # Matched on the changeset's resource module (an atom), not on struct patterns: a
  # struct pattern would make this change a compile-time dependent of the resources
  # that use it.
  defp workspace_id(%{id: id}, %{resource: TeacherAssistant.Academics.Workspace}), do: id
  defp workspace_id(%{workspace_id: id}, _changeset) when is_binary(id), do: id
  defp workspace_id(_record, %{tenant: tenant}) when is_binary(tenant), do: tenant
  defp workspace_id(_record, _changeset), do: nil

  defp target_user_id(%{resource: TeacherAssistant.Accounts.User}, %{id: id}), do: id
  defp target_user_id(_changeset, _record), do: nil

  defp details(:modules_changed, before, record),
    do: %{"before" => names(before.modules), "after" => names(record.modules)}

  defp details(:school_suspended, _before, record), do: %{"reason" => record.suspension_reason}
  defp details(:school_rejected, _before, record), do: %{"reason" => record.rejection_reason}
  defp details(_action, _before, _record), do: %{}

  defp names(modules), do: Enum.map(modules || [], &to_string/1)
end
