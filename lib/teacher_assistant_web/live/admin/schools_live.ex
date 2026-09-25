defmodule TeacherAssistantWeb.Admin.SchoolsLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.{SchoolType, SchoolSubsystem, SchoolSector, CameroonRegion}

  def mount(_params, _session, socket) do
    {:ok, reload_schools(socket)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-schools" class="space-y-6">
        <.page_header
          eyebrow={gettext("Opérateur")}
          title={gettext("Établissements à vérifier")}
        />

        <.empty_state
          :if={@schools == []}
          icon="hero-check-badge"
          title={gettext("Aucun établissement en attente de vérification")}
        />

        <div
          :for={p <- @schools}
          id={"school-row-#{p.workspace_id}"}
          class="ta-leaf space-y-3 p-4"
        >
          <div class="flex flex-wrap items-start justify-between gap-4">
            <div class="space-y-1">
              <h2 class="font-semibold">{p.workspace.name}</h2>
              <p class="text-sm text-base-content/70">
                {SchoolType.label(p.school_type)} · {SchoolSubsystem.label(p.subsystem)} · {SchoolSector.label(
                  p.sector
                )} · {CameroonRegion.label(p.region)} · {p.town}
              </p>
              <p class="text-sm text-base-content/60">{p.owner_user.email}</p>
            </div>

            <div class="flex flex-col items-end gap-2">
              <button
                id={"verify-#{p.workspace_id}"}
                type="button"
                class="btn btn-primary btn-sm"
                phx-click="verify"
                phx-value-id={p.workspace_id}
              >
                {gettext("Vérifier")}
              </button>

              <form
                id={"reject-#{p.workspace_id}"}
                phx-submit="reject"
                class="flex items-center gap-2"
              >
                <input type="hidden" name="workspace_id" value={p.workspace_id} />
                <input
                  type="text"
                  name="reason"
                  placeholder={gettext("Motif du rejet")}
                  class="input input-bordered input-sm"
                />
                <button type="submit" class="btn btn-ghost btn-sm">{gettext("Rejeter")}</button>
              </form>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("verify", %{"id" => workspace_id}, socket) do
    case find_profile(socket, workspace_id) do
      nil ->
        {:noreply, socket}

      profile ->
        scope = socket.assigns.current_scope

        {:ok, _} =
          Accounts.verify_school(profile, scope.current_user.id, scope: scope)

        {:noreply, reload_schools(socket)}
    end
  end

  def handle_event("reject", %{"workspace_id" => workspace_id, "reason" => reason}, socket) do
    case find_profile(socket, workspace_id) do
      nil ->
        {:noreply, socket}

      profile ->
        scope = socket.assigns.current_scope

        {:ok, _} =
          Accounts.reject_school(
            profile,
            scope.current_user.id,
            reason,
            scope: scope
          )

        {:noreply, reload_schools(socket)}
    end
  end

  defp find_profile(socket, workspace_id) do
    Enum.find(socket.assigns.schools, &(to_string(&1.workspace_id) == to_string(workspace_id)))
  end

  defp reload_schools(socket),
    do: assign(socket, :schools, Accounts.list_unverified_schools(socket.assigns.current_scope))
end
