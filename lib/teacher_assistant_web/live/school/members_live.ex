defmodule TeacherAssistantWeb.School.MembersLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.{Permissions, SchoolRoles, Schools}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Permissions.member?(scope) do
      {:ok,
       socket
       |> assign(:scope, scope)
       |> assign(:head?, Permissions.head?(scope))
       |> assign(:invite_form, to_form(%{"email" => "", "roles" => ["teacher"]}, as: :invite))
       |> reload_members()}
    else
      {:ok, push_navigate(socket, to: ~p"/teacher")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="school-members" class="space-y-6">
        <.page_header eyebrow={gettext("École")} title={gettext("Membres")} />

        <div class="overflow-x-auto">
          <table id="members-table" class="table table-zebra">
            <thead>
              <tr>
                <th>{gettext("Nom")}</th>
                <th>{gettext("Rôles")}</th>
                <th>{gettext("Statut")}</th>
                <th :if={@head?}><span class="sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={m <- @members} id={"member-row-#{m.id}"}>
                <td>{m.user.email}</td>
                <td>
                  <form
                    :if={@head?}
                    phx-change="set_roles"
                    phx-value-id={m.id}
                    class="flex flex-wrap gap-2"
                  >
                    <label :for={role <- SchoolRoles.all()} class="label cursor-pointer gap-1">
                      <input
                        type="checkbox"
                        name="roles[]"
                        value={role}
                        checked={role in m.roles}
                        class="checkbox checkbox-sm"
                      />
                      <span class="text-xs">{SchoolRoles.label(role)}</span>
                    </label>
                  </form>
                  <span :if={!@head?}>
                    {m.roles |> Enum.map(&SchoolRoles.label/1) |> Enum.join(", ")}
                  </span>
                </td>
                <td>{gettext("Actif")}</td>
                <td :if={@head?}>
                  <button
                    id={"member-deactivate-#{m.id}"}
                    type="button"
                    class="btn btn-ghost btn-xs"
                    phx-click="deactivate_member"
                    phx-value-id={m.id}
                    data-confirm={gettext("Désactiver ce membre ?")}
                  >
                    {gettext("Désactiver")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.empty_state
          :if={@members == []}
          icon="hero-user-group"
          title={gettext("Aucun membre actif pour le moment")}
        />

        <div :if={@head?} class="ta-leaf space-y-3">
          <h2 class="text-sm font-semibold">{gettext("Inviter un membre")}</h2>
          <.form for={@invite_form} id="invite-form" phx-submit="invite">
            <div class="flex flex-wrap items-end gap-3">
              <.input field={@invite_form[:email]} type="email" label={gettext("Email")} />
              <div class="flex flex-wrap gap-2">
                <label :for={role <- SchoolRoles.all()} class="label cursor-pointer gap-1">
                  <input
                    type="checkbox"
                    name="invite[roles][]"
                    value={role}
                    checked={role == :teacher}
                    class="checkbox checkbox-sm"
                  />
                  <span class="text-xs">{SchoolRoles.label(role)}</span>
                </label>
              </div>
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Inviter")}</button>
            </div>
          </.form>
        </div>

        <div :if={@head?} id="invitations-list" class="space-y-2">
          <h2 class="text-sm font-semibold">{gettext("Invitations en attente")}</h2>
          <.empty_state
            :if={@invitations == []}
            icon="hero-envelope"
            title={gettext("Aucune invitation en attente")}
          />
          <div
            :for={inv <- @invitations}
            id={"invitation-#{inv.id}"}
            class="flex items-center justify-between gap-3 rounded-lg border border-base-300 px-3 py-2"
          >
            <div class="text-sm">
              <span class="font-medium">{inv.email}</span>
              <span class="text-base-content/60">
                — {inv.roles |> Enum.map(&SchoolRoles.label/1) |> Enum.join(", ")}
              </span>
            </div>
            <button
              id={"invite-revoke-#{inv.id}"}
              type="button"
              class="btn btn-ghost btn-xs"
              phx-click="revoke_invite"
              phx-value-id={inv.id}
              data-confirm={gettext("Révoquer cette invitation ?")}
            >
              {gettext("Révoquer")}
            </button>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("invite", %{"invite" => params}, socket) do
    scope = socket.assigns.scope

    if Permissions.head?(scope) do
      roles = parse_roles(params["roles"])

      case Schools.invite_member(scope.current_workspace, scope.current_user, %{
             email: params["email"],
             roles: roles
           }) do
        {:ok, _invitation} ->
          {:noreply, reload_members(socket)}

        {:error, :already_member} ->
          {:noreply,
           put_flash(socket, :error, gettext("Cette personne est déjà membre de l'école."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("revoke_invite", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    if Permissions.head?(scope) do
      case find_invitation(scope.current_workspace, id) do
        nil ->
          {:noreply, socket}

        inv ->
          {:ok, _} = Schools.revoke_invitation(inv)
          {:noreply, reload_members(socket)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("deactivate_member", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    if Permissions.head?(scope) do
      case find_membership(scope.current_workspace, id) do
        nil ->
          {:noreply, socket}

        membership ->
          case Schools.deactivate_member(membership) do
            {:ok, _} ->
              {:noreply, reload_members(socket)}

            {:error, :last_head} ->
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 gettext("Impossible de désactiver le dernier chef d'établissement.")
               )}
          end
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_roles", %{"id" => id} = params, socket) do
    scope = socket.assigns.scope

    if Permissions.head?(scope) do
      roles = parse_roles(params["roles"])

      case find_membership(scope.current_workspace, id) do
        nil ->
          {:noreply, socket}

        membership ->
          case Schools.update_member_roles(membership, roles) do
            {:ok, _} ->
              {:noreply, reload_members(socket)}

            {:error, :last_head} ->
              {:noreply,
               put_flash(
                 socket,
                 :error,
                 gettext("Impossible de retirer le rôle de chef d'établissement du dernier chef.")
               )}
          end
      end
    else
      {:noreply, socket}
    end
  end

  defp reload_members(socket) do
    school = socket.assigns.scope.current_workspace

    socket
    |> assign(:members, Schools.list_members(school))
    |> assign(:invitations, Schools.list_pending_invitations(school))
  end

  defp parse_roles(nil), do: [:teacher]
  defp parse_roles([]), do: [:teacher]

  defp parse_roles(roles) when is_list(roles) do
    roles
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&String.to_existing_atom/1)
    |> case do
      [] -> [:teacher]
      parsed -> parsed
    end
  end

  defp find_invitation(school, id) do
    school
    |> Schools.list_pending_invitations()
    |> Enum.find(&(to_string(&1.id) == to_string(id)))
  end

  defp find_membership(school, id) do
    school
    |> Schools.list_members()
    |> Enum.find(&(to_string(&1.id) == to_string(id)))
  end
end
