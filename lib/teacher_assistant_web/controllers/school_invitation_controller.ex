defmodule TeacherAssistantWeb.SchoolInvitationController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts

  def show(conn, %{"token" => token}) do
    case Accounts.fetch_invitation_by_token(token) do
      {:ok, invitation} ->
        current_user = conn.assigns.current_user

        {auth_state, conn} =
          cond do
            is_nil(current_user) ->
              {:signed_out, put_session(conn, :return_to, ~p"/schools/invitations/#{token}")}

            to_string(current_user.email) == to_string(invitation.email) ->
              {:match, conn}

            true ->
              {:mismatch, conn}
          end

        conn
        |> render(:show,
          invitation: invitation,
          school_name: invitation.workspace.name,
          current_user: current_user,
          auth_state: auth_state
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, gettext("Cette invitation est introuvable ou a expiré."))
        |> redirect(to: ~p"/school")
    end
  end

  def accept(%{assigns: %{current_user: nil}} = conn, %{"token" => token}) do
    conn
    |> put_session(:return_to, ~p"/schools/invitations/#{token}")
    |> redirect(to: ~p"/sign-in")
  end

  def accept(conn, %{"token" => token}) do
    case Accounts.accept_invitation(token, conn.assigns.current_user) do
      {:ok, school} ->
        conn
        |> put_session(:workspace_id, school.id)
        |> redirect(to: ~p"/school")

      {:error, reason} ->
        conn
        |> put_flash(:error, error_message(reason))
        |> redirect(to: ~p"/school")
    end
  end

  defp error_message(:invalid), do: gettext("Cette invitation est invalide.")
  defp error_message(:expired), do: gettext("Cette invitation a expiré.")

  defp error_message(:email_mismatch),
    do: gettext("Cette invitation a été envoyée à une autre adresse email.")

  defp error_message(_), do: gettext("Impossible d'accepter cette invitation.")
end
