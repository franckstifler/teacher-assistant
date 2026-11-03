defmodule TeacherAssistantWeb.Impersonation do
  @moduledoc """
  The operator acting as a school member, to help them (enter marks, fix a setting).

  The operator stays signed in as themselves; the session's `:impersonation` key names the
  member, the school and the start time. `TeacherAssistantWeb.Plug.Scope` and
  `TeacherAssistantWeb.LiveUserAuth` then build the member's scope instead of the
  operator's, so every policy applies as the member and what is entered is theirs. It holds
  only while the signed-in user is still an operator, and for an hour; after
  that `TeacherAssistantWeb.Plug.EndImpersonation` ends it on the next request. Start
  and end are journaled; the school is never told.
  """
  import Plug.Conn

  alias TeacherAssistant.{Accounts, Operator, Scope}
  alias TeacherAssistant.Accounts.User

  @seconds 3600

  @doc "The session value for acting as `user` in `workspace`, started at `started_at`."
  def session_value(user_id, workspace_id, return_workspace_id, started_at \\ now()) do
    %{
      "user_id" => user_id,
      "workspace_id" => workspace_id,
      "return_workspace_id" => return_workspace_id,
      "started_at" => started_at
    }
  end

  @doc """
  What the session's value means for the signed-in `user`: `{:acting, member, impersonation}`
  (`impersonation` as `Scope.impersonation`), `:none`, or `:ended` (expired, the user is no
  longer an operator, or the member can no longer be acted as).
  """
  def resolve(_user, nil), do: :none

  def resolve(%User{role: :admin} = operator, %{"user_id" => id, "started_at" => started_at}) do
    ends_at = started_at + @seconds

    with true <- now() < ends_at,
         %User{} = member <- Operator.impersonated_user(%Scope{current_user: operator}, id) do
      {:acting, member, %{operator: operator, ends_at: DateTime.from_unix!(ends_at)}}
    else
      _ -> :ended
    end
  end

  def resolve(_user, _value), do: :ended

  @doc "Milliseconds left before `impersonation` ends."
  def remaining_ms(%{ends_at: ends_at}),
    do: max(DateTime.diff(ends_at, DateTime.utc_now(), :millisecond), 0)

  @doc """
  Ends the session's impersonation, if any: journals it with `reason` (when the signed-in
  user is still an operator), gives the operator back the school they were in, and drops
  the live pages still showing the member.
  """
  def stop(conn, reason) do
    case {get_session(conn, :impersonation), conn.assigns[:current_user]} do
      {nil, _user} ->
        conn

      {value, user} ->
        if match?(%User{role: :admin}, user) do
          Operator.end_impersonation(
            %Scope{current_user: user},
            value["user_id"],
            value["workspace_id"],
            reason
          )

          Accounts.disconnect_live_pages(user)
        end

        conn
        |> delete_session(:impersonation)
        |> delete_session(:context_id)
        |> delete_session(:space)
        |> restore_workspace(value["return_workspace_id"])
    end
  end

  defp restore_workspace(conn, nil), do: delete_session(conn, :workspace_id)
  defp restore_workspace(conn, id), do: put_session(conn, :workspace_id, id)

  defp now, do: System.os_time(:second)
end
