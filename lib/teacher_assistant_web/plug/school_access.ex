defmodule TeacherAssistantWeb.Plug.SchoolAccess do
  @moduledoc """
  Operator console spec §1–2 for controller routes: a suspended school's member goes to
  `/school/suspended`; an action of a module the school does not have redirects home.
  Used inside each school controller (`plug TeacherAssistantWeb.Plug.SchoolAccess`),
  where the controller and the action are known.
  """
  @behaviour Plug

  use TeacherAssistantWeb, :verified_routes
  use Gettext, backend: TeacherAssistantWeb.Gettext

  import Plug.Conn
  import Phoenix.Controller

  alias TeacherAssistant.{Modules, Scope}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    scope = conn.assigns[:current_scope]
    key = Modules.module_for_controller(controller_module(conn), action_name(conn))

    cond do
      Scope.suspended?(scope) ->
        conn |> redirect(to: ~p"/school/suspended") |> halt()

      key in [nil, :core] or Scope.module?(scope, key) ->
        conn

      true ->
        conn
        |> put_flash(:error, gettext("Ce module n'est pas activé pour votre établissement."))
        |> redirect(to: ~p"/school")
        |> halt()
    end
  end
end
