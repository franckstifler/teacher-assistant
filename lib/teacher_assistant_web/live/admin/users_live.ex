defmodule TeacherAssistantWeb.Admin.UsersLive do
  @moduledoc "Operator console spec §3, §5: find anyone across schools and reset their password."
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.Admin.ResetModal, only: [reset_modal: 1]

  alias TeacherAssistant.{Accounts, Operator}
  alias TeacherAssistant.Accounts.SchoolRole

  def mount(_params, _session, socket),
    do:
      {:ok,
       assign(socket,
         page_title: gettext("Utilisateurs"),
         q: "",
         results: [],
         reset_user: nil,
         reset_password: nil
       )}

  def handle_event("search", %{"q" => q}, socket),
    do:
      {:noreply,
       assign(socket, q: q, results: Operator.search_users(socket.assigns.current_scope, q))}

  def handle_event("reset_ask", %{"id" => id}, socket) do
    case Operator.get_user(socket.assigns.current_scope, id) do
      {:ok, user} -> {:noreply, assign(socket, reset_user: user, reset_password: nil)}
      {:error, :not_found} -> {:noreply, socket}
    end
  end

  def handle_event("reset_confirm", _params, %{assigns: %{reset_user: %{} = user}} = socket) do
    case Accounts.operator_reset_password(socket.assigns.current_scope, user) do
      {:ok, password} ->
        {:noreply, assign(socket, :reset_password, password)}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(reset_user: nil)
         |> put_flash(:error, gettext("Réinitialisation impossible."))}
    end
  end

  def handle_event("reset_confirm", _params, socket), do: {:noreply, socket}

  def handle_event("reset_cancel", _params, socket) do
    %{current_scope: scope, q: q} = socket.assigns

    {:noreply,
     assign(socket,
       reset_user: nil,
       reset_password: nil,
       results: Operator.search_users(scope, q)
     )}
  end

  defp schools_line(memberships) do
    Enum.map_join(memberships, " · ", fn m ->
      "#{m.workspace.name} (#{Enum.map_join(m.roles, ", ", &SchoolRole.label/1)})"
    end)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-users" class="space-y-6">
        <.page_header eyebrow={gettext("Administration")} title={gettext("Utilisateurs")} />

        <form id="users-search" phx-change="search" phx-submit="search">
          <input
            type="search"
            name="q"
            value={@q}
            phx-debounce="300"
            placeholder={gettext("Nom, téléphone ou e-mail")}
            aria-label={gettext("Rechercher un utilisateur")}
            class="input input-bordered w-full"
          />
        </form>

        <ul class="divide-y divide-base-300">
          <li
            :for={%{user: u, memberships: ms} <- @results}
            id={"user-#{u.id}"}
            class="flex flex-wrap items-center justify-between gap-2 py-3"
          >
            <span>
              <span class="font-medium">{Accounts.User.display_name(u)}</span>
              <span class="text-sm text-base-content/70"> · {Accounts.User.contact(u)}</span>
              <span :if={u.role == :admin} class="badge badge-xs">{gettext("Opérateur")}</span>
              <span :if={u.must_change_password} class="badge badge-warning badge-xs">
                {gettext("Mot de passe temporaire")}
              </span>
              <span class="block text-sm text-base-content/70">{schools_line(ms)}</span>
              <span :if={u.role != :admin} class="mt-1 flex flex-wrap gap-1">
                <.link
                  :for={m <- ms}
                  id={"impersonate-#{u.id}-#{m.workspace_id}"}
                  href={~p"/impersonation?#{%{user_id: u.id, workspace_id: m.workspace_id}}"}
                  method="post"
                  class="btn btn-ghost btn-xs"
                >
                  <.icon name="hero-eye" class="size-3.5" />
                  {gettext("Ouvrir en tant que · %{school}", school: m.workspace.name)}
                </.link>
              </span>
            </span>
            <button
              :if={u.role != :admin}
              id={"reset-user-#{u.id}"}
              type="button"
              class="btn btn-ghost btn-xs"
              phx-click="reset_ask"
              phx-value-id={u.id}
            >
              {gettext("Réinitialiser le mot de passe")}
            </button>
          </li>
        </ul>

        <.reset_modal :if={@reset_user} user={@reset_user} password={@reset_password} />
      </section>
    </Layouts.app>
    """
  end
end
