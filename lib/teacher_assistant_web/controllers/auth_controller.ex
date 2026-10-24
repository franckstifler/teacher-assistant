defmodule TeacherAssistantWeb.AuthController do
  use TeacherAssistantWeb, :controller
  use AshAuthentication.Phoenix.Controller

  require Logger

  def success(conn, activity, user, _token) do
    if TeacherAssistant.Accounts.temporary_password_expired?(user) do
      # The temporary password was correct but is past its 7 days: no session.
      case TeacherAssistant.Accounts.revoke_all_sessions(user) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Could not revoke sessions after an expired temporary password for user #{user.id}: #{inspect(reason)}"
          )
      end

      conn
      |> put_flash(
        :error,
        gettext("Mot de passe temporaire expiré — demandez-en un nouveau à l'établissement.")
      )
      |> redirect(to: ~p"/sign-in")
    else
      sign_in(conn, activity, user)
    end
  end

  def failure(conn, activity, reason) do
    message =
      case {activity, reason} do
        {_,
         %AshAuthentication.Errors.AuthenticationFailed{
           caused_by: %Ash.Error.Forbidden{
             errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
           }
         }} ->
          gettext(
            "You have already signed in another way, but have not confirmed your account. You can confirm your account using the link we sent to you, or by resetting your password."
          )

        _ ->
          gettext("Identifiant ou mot de passe incorrect")
      end

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  defp sign_in(conn, activity, user) do
    return_to = get_session(conn, :return_to) || ~p"/school"

    message =
      case activity do
        {:confirm_new_user, :confirm} -> gettext("Your email address has now been confirmed")
        {:password, :reset} -> gettext("Your password has successfully been reset")
        _ -> gettext("You are now signed in")
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> put_session(:live_socket_id, TeacherAssistant.Accounts.live_socket_id(user))
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: return_to)
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    # Other tabs of this browser lose their session with the cookie: drop their
    # live pages now rather than at their next reconnect. (Other devices just
    # reconnect, still signed in.)
    if user = conn.assigns[:current_user],
      do: TeacherAssistant.Accounts.disconnect_live_pages(user)

    conn
    |> clear_session(:teacher_assistant)
    |> put_flash(:info, gettext("You are now signed out"))
    |> redirect(to: return_to)
  end
end
