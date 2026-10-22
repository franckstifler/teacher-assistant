defmodule TeacherAssistantWeb.Admin.SchoolLive do
  @moduledoc """
  Operator console spec §5: one school — verification, suspension, modules, counts,
  members with password reset, and its journal.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.Admin.ResetModal, only: [reset_modal: 1]

  alias TeacherAssistant.{Accounts, Modules, Operator, Organization}
  alias TeacherAssistant.Accounts.{AuditEvent, SchoolRole, SchoolVerificationStatus}
  alias TeacherAssistantWeb.Dates

  def mount(%{"id" => id}, _session, socket) do
    case Operator.get_school(socket.assigns.current_scope, id) do
      {:ok, school} ->
        {:ok, socket |> assign(reset_user: nil, reset_password: nil) |> assign_school(school)}

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/admin/schools")}
    end
  end

  def handle_event("verify", _params, socket) do
    %{current_scope: scope, school: %{profile: profile}} = socket.assigns
    decided(socket, Accounts.verify_school(profile, scope.current_user.id, scope: scope))
  end

  def handle_event("reject", %{"reason" => reason}, socket) do
    %{current_scope: scope, school: %{profile: profile}} = socket.assigns
    decided(socket, Accounts.reject_school(profile, scope.current_user.id, reason, scope: scope))
  end

  # The hidden empty value keeps `modules` in the params when every box is unchecked;
  # it matches no key and is dropped.
  def handle_event("save_modules", params, socket) do
    modules =
      params
      |> Map.get("modules", [])
      |> Enum.flat_map(fn m ->
        case Modules.Key.match(m) do
          {:ok, key} -> [key]
          :error -> []
        end
      end)

    %{current_scope: scope, school: %{workspace: ws}} = socket.assigns
    decided(socket, Organization.set_modules(scope, ws, modules))
  end

  def handle_event("suspend", %{"reason" => reason}, socket) do
    %{current_scope: scope, school: %{workspace: ws}} = socket.assigns

    case Organization.suspend_school(scope, ws, reason) do
      {:ok, _} ->
        {:noreply, reload(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Indiquez le motif de la suspension."))}
    end
  end

  def handle_event("reactivate", _params, socket) do
    %{current_scope: scope, school: %{workspace: ws}} = socket.assigns
    decided(socket, Organization.reactivate_school(scope, ws))
  end

  def handle_event("reset_ask", %{"id" => id}, socket) do
    user = Enum.find_value(socket.assigns.school.members, &(&1.user_id == id && &1.user))
    {:noreply, assign(socket, reset_user: user, reset_password: nil)}
  end

  def handle_event("reset_confirm", _params, %{assigns: %{reset_user: %{} = user}} = socket) do
    %{current_scope: scope, school: %{workspace: ws}} = socket.assigns

    case Accounts.operator_reset_password(scope, user, ws.id) do
      {:ok, password} ->
        {:noreply, socket |> assign(:reset_password, password) |> reload()}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(reset_user: nil)
         |> put_flash(:error, gettext("Réinitialisation impossible."))}
    end
  end

  def handle_event("reset_confirm", _params, socket), do: {:noreply, socket}

  def handle_event("reset_cancel", _params, socket),
    do: {:noreply, assign(socket, reset_user: nil, reset_password: nil)}

  defp decided(socket, {:ok, _}), do: {:noreply, reload(socket)}

  defp decided(socket, {:error, _}),
    do: {:noreply, put_flash(socket, :error, gettext("Impossible d'enregistrer la décision."))}

  defp reload(socket) do
    {:ok, school} =
      Operator.get_school(socket.assigns.current_scope, socket.assigns.school.workspace.id)

    assign_school(socket, school)
  end

  defp assign_school(socket, school) do
    assign(socket,
      school: school,
      events:
        Accounts.list_audit_events(socket.assigns.current_scope,
          workspace_id: school.workspace.id,
          limit: 20
        )
    )
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-school" class="space-y-6">
        <.page_header eyebrow={gettext("Établissement")} title={@school.workspace.name} />

        <div class="flex flex-wrap items-center gap-2">
          <span id="school-verification" class="badge">
            {SchoolVerificationStatus.label(@school.profile.verification_status)}
          </span>
          <span
            :if={@school.workspace.suspended_at}
            id="school-suspended-badge"
            class="badge badge-error"
          >
            {gettext("Suspendu : %{reason}", reason: @school.workspace.suspension_reason)}
          </span>
        </div>

        <section class="ta-leaf space-y-3 p-4">
          <h2 class="font-semibold">{gettext("Vérification")}</h2>
          <button
            :if={@school.profile.verification_status != :verified}
            id="verify-school"
            type="button"
            class="btn btn-primary btn-sm"
            phx-click="verify"
          >
            {gettext("Vérifier")}
          </button>
          <form
            :if={@school.profile.verification_status == :unverified}
            id="reject-form"
            phx-submit="reject"
            class="flex flex-wrap gap-2"
          >
            <input
              type="text"
              name="reason"
              placeholder={gettext("Motif du rejet")}
              aria-label={gettext("Motif du rejet")}
              class="input input-bordered input-sm"
            />
            <button type="submit" class="btn btn-ghost btn-sm">{gettext("Rejeter")}</button>
          </form>
        </section>

        <section class="ta-leaf space-y-3 p-4">
          <h2 class="font-semibold">{gettext("Accès")}</h2>
          <form
            :if={is_nil(@school.workspace.suspended_at)}
            id="suspend-form"
            phx-submit="suspend"
            class="flex flex-wrap gap-2"
          >
            <input
              type="text"
              name="reason"
              placeholder={gettext("Motif de la suspension")}
              aria-label={gettext("Motif de la suspension")}
              class="input input-bordered input-sm"
            />
            <button type="submit" class="btn btn-error btn-sm">{gettext("Suspendre")}</button>
          </form>
          <button
            :if={@school.workspace.suspended_at}
            id="reactivate-school"
            type="button"
            class="btn btn-primary btn-sm"
            phx-click="reactivate"
          >
            {gettext("Réactiver")}
          </button>
        </section>

        <form id="modules-form" phx-submit="save_modules" class="ta-leaf space-y-3 p-4">
          <h2 class="font-semibold">{gettext("Modules")}</h2>
          <%!-- Posted even when every box is unchecked, so « none » reaches the server. --%>
          <input type="hidden" name="modules[]" value="" />
          <label :for={k <- Modules.keys()} class="label cursor-pointer justify-start gap-2">
            <input
              type="checkbox"
              id={"module-#{k}"}
              name="modules[]"
              value={k}
              checked={k in @school.workspace.modules}
              class="checkbox checkbox-sm"
            />
            {Modules.label(k)}
          </label>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
        </form>

        <dl id="school-counts" class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div class="ta-leaf p-3">
            <dt class="text-sm text-base-content/70">{gettext("Classes")}</dt>
            <dd class="ta-num text-lg font-semibold">{@school.counts.classes}</dd>
          </div>
          <div class="ta-leaf p-3">
            <dt class="text-sm text-base-content/70">{gettext("Élèves")}</dt>
            <dd class="ta-num text-lg font-semibold">{@school.counts.students}</dd>
          </div>
          <div class="ta-leaf p-3">
            <dt class="text-sm text-base-content/70">{gettext("Personnel")}</dt>
            <dd class="ta-num text-lg font-semibold">{@school.counts.staff}</dd>
          </div>
          <div class="ta-leaf p-3">
            <dt class="text-sm text-base-content/70">{gettext("Dernière activité")}</dt>
            <dd>
              {if @school.last_activity, do: Dates.short_datetime(@school.last_activity), else: "—"}
            </dd>
          </div>
        </dl>

        <section class="space-y-2">
          <h2 class="font-semibold">{gettext("Membres")}</h2>
          <ul id="school-members" class="divide-y divide-base-300">
            <li
              :for={m <- @school.members}
              id={"member-#{m.user_id}"}
              class="flex flex-wrap items-center justify-between gap-2 py-2"
            >
              <span>
                <span class="font-medium">{Accounts.User.display_name(m.user)}</span>
                <span class="text-sm text-base-content/70">
                  · {Enum.map_join(m.roles, ", ", &SchoolRole.label/1)} · {Accounts.User.contact(
                    m.user
                  )}
                </span>
                <span :if={m.user.must_change_password} class="badge badge-warning badge-xs">
                  {gettext("Mot de passe temporaire")}
                </span>
              </span>
              <button
                :if={m.user.role != :admin}
                id={"reset-user-#{m.user_id}"}
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="reset_ask"
                phx-value-id={m.user_id}
              >
                {gettext("Réinitialiser le mot de passe")}
              </button>
            </li>
          </ul>
        </section>

        <section class="space-y-2">
          <h2 class="font-semibold">{gettext("Journal")}</h2>
          <ul id="school-events" class="divide-y divide-base-300 text-sm">
            <li :for={e <- @events} id={"event-#{e.id}"} class="py-2">
              {AuditEvent.Action.label(e.action)}
              <span :if={e.target_user}> · {Accounts.User.display_name(e.target_user)}</span>
              <span class="text-base-content/70"> · {Dates.short_datetime(e.inserted_at)}</span>
            </li>
          </ul>
        </section>

        <.reset_modal :if={@reset_user} user={@reset_user} password={@reset_password} />
      </section>
    </Layouts.app>
    """
  end
end
