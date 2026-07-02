defmodule TeacherAssistantWeb.SchoolInvitationController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts.Schools

  def show(conn, %{"token" => token}) do
    case Schools.fetch_invitation_by_token(token) do
      {:ok, invitation} ->
        current_user = conn.assigns[:current_user]
        email_match? = current_user && to_string(current_user.email) == to_string(invitation.email)

        conn
        |> render(:show,
          invitation: invitation,
          school_name: invitation.workspace.name,
          current_user: current_user,
          email_match?: email_match?
        )

      {:error, :not_found} ->
        conn
        |> put_flash(:error, gettext("Cette invitation est introuvable ou a expiré."))
        |> redirect(to: ~p"/teacher")
    end
  end

  def accept(conn, %{"token" => token}) do
    user = conn.assigns[:current_user] || load_user(get_session(conn, :user_id))
    conn = assign(conn, :current_user, user)

    case Schools.accept_invitation(token, user) do
      {:ok, school} ->
        conn
        |> put_session(:workspace_id, school.id)
        |> redirect(to: ~p"/school")

      {:error, reason} ->
        conn
        |> put_flash(:error, error_message(reason))
        |> redirect(to: ~p"/teacher")
    end
  end

  defp error_message(:invalid), do: gettext("Cette invitation est invalide.")
  defp error_message(:expired), do: gettext("Cette invitation a expiré.")
  defp error_message(:email_mismatch), do: gettext("Cette invitation a été envoyée à une autre adresse email.")
  defp error_message(_), do: gettext("Impossible d'accepter cette invitation.")

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Ash.get(TeacherAssistant.Accounts.User, user_id, authorize?: false) do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
