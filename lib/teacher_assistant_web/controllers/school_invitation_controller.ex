defmodule TeacherAssistantWeb.SchoolInvitationController do
  use TeacherAssistantWeb, :controller

  alias TeacherAssistant.Accounts

  def show(conn, %{"token" => token}) do
    case Accounts.fetch_invitation_by_token(token) do
      {:ok, invitation} ->
        current_user = resolve_current_user(conn)

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
        |> redirect(to: ~p"/teacher")
    end
  end

  def accept(conn, %{"token" => token}) do
    user = resolve_current_user(conn)
    conn = assign(conn, :current_user, user)

    case Accounts.accept_invitation(token, user) do
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

  defp error_message(:email_mismatch),
    do: gettext("Cette invitation a été envoyée à une autre adresse email.")

  defp error_message(_), do: gettext("Impossible d'accepter cette invitation.")

  # Prefers the (real AshAuthentication) `:current_user` assign, but falls back to
  # the session's plain `:user_id` — the shape our test helpers and the accept/2
  # flow have always signed conns in with.
  defp resolve_current_user(conn) do
    conn.assigns[:current_user] || load_user(get_session(conn, :user_id))
  end

  defp load_user(nil), do: nil

  defp load_user(user_id) do
    case Ash.get(TeacherAssistant.Accounts.User, user_id) do
      {:ok, user} -> user
      _ -> nil
    end
  end
end
