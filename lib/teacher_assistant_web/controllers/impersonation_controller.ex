defmodule TeacherAssistantWeb.ImpersonationController do
  @moduledoc """
  The operator starts and stops acting as a school member
  (`TeacherAssistantWeb.Impersonation`). Both write the session: POST and DELETE only.
  """
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.{Accounts, Operator, Scope}
  alias TeacherAssistantWeb.Impersonation

  def create(conn, %{"user_id" => user_id, "workspace_id" => workspace_id}) do
    case conn.assigns[:current_user] do
      %Accounts.User{role: :admin} = operator ->
        conn = Impersonation.stop(conn, "replaced")

        case Operator.start_impersonation(%Scope{current_user: operator}, user_id, workspace_id) do
          {:ok, %{user: user, workspace: ws}} ->
            conn
            |> put_session(
              :impersonation,
              Impersonation.session_value(user.id, ws.id, get_session(conn, :workspace_id))
            )
            |> put_session(:workspace_id, ws.id)
            |> delete_session(:context_id)
            |> delete_session(:space)
            |> redirect(to: ~p"/school")

          {:error, _} ->
            conn
            |> put_flash(:error, gettext("Impossible d'ouvrir ce compte."))
            |> redirect(to: ~p"/admin/schools/#{workspace_id}")
        end

      _ ->
        redirect(conn, to: ~p"/")
    end
  end

  def delete(conn, _params) do
    workspace_id = get_in(get_session(conn, :impersonation) || %{}, ["workspace_id"])

    conn
    |> Impersonation.stop("stopped")
    |> redirect(to: if(workspace_id, do: ~p"/admin/schools/#{workspace_id}", else: ~p"/admin"))
  end
end
