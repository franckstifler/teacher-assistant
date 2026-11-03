defmodule TeacherAssistantWeb.Plug.EndImpersonation do
  @moduledoc """
  Ends an impersonation that no longer holds (`TeacherAssistantWeb.Impersonation.resolve/2`
  says `:ended`: the hour is over, or the signed-in user is no longer an operator) on the
  first request after, and sends the operator back to the console. Signing out just goes
  on. Runs after `load_from_session`.
  """
  @behaviour Plug
  use TeacherAssistantWeb, :verified_routes
  use Gettext, backend: TeacherAssistantWeb.Gettext

  import Plug.Conn

  alias TeacherAssistantWeb.Impersonation

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    case Impersonation.resolve(user, get_session(conn, :impersonation)) do
      :ended ->
        conn = Impersonation.stop(conn, "expired")

        if conn.request_path == ~p"/sign-out" do
          conn
        else
          conn
          |> Phoenix.Controller.put_flash(
            :info,
            gettext("L'accès en tant que ce membre a pris fin.")
          )
          |> Phoenix.Controller.redirect(
            to: if(user && user.role == :admin, do: ~p"/admin", else: ~p"/")
          )
          |> halt()
        end

      _ ->
        conn
    end
  end
end
