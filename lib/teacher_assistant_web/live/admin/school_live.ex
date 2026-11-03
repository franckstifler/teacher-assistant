defmodule TeacherAssistantWeb.Admin.SchoolLive do
  @moduledoc """
  Operator console spec §5: one school — its status and figures in one line, the members
  (search, « Mot de passe temporaire » filter, « ⋯ » menu to open as or reset), and on the
  side its modules with their 30-day use, its journal and the suspension. Verification
  stays for a school not yet verified.
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.Admin.ResetModal, only: [reset_modal: 1]
  import TeacherAssistantWeb.Admin.AdminComponents
  import TeacherAssistantWeb.Modal

  alias Phoenix.LiveView.JS
  alias TeacherAssistant.{Accounts, Modules, Operator, Organization}
  alias TeacherAssistant.Accounts.{AuditEvent, CameroonRegion, SchoolRole, SchoolType, User}
  alias TeacherAssistantWeb.Dates

  def mount(%{"id" => id}, _session, socket) do
    case Operator.get_school(socket.assigns.current_scope, id) do
      {:ok, school} ->
        {:ok,
         socket
         |> assign(
           reset_user: nil,
           reset_password: nil,
           suspend_open?: false,
           q: "",
           temp?: false
         )
         |> assign_school(school)}

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/admin/schools")}
    end
  end

  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(q: String.trim(params["q"] || ""), temp?: params["temp"] == "1")
     |> assign_members()}
  end

  def handle_event("search", %{"q" => q}, socket) do
    %{school: %{workspace: ws}, temp?: temp?} = socket.assigns
    {:noreply, push_patch(socket, to: self_path(ws.id, q, temp?), replace: true)}
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

  def handle_event("suspend_ask", _params, socket),
    do: {:noreply, assign(socket, suspend_open?: true)}

  def handle_event("suspend_cancel", _params, socket),
    do: {:noreply, assign(socket, suspend_open?: false)}

  def handle_event("suspend", %{"reason" => reason}, socket) do
    %{current_scope: scope, school: %{workspace: ws}} = socket.assigns

    case Organization.suspend_school(scope, ws, reason) do
      {:ok, _} ->
        {:noreply, socket |> assign(suspend_open?: false) |> reload()}

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

    socket |> assign_school(school) |> assign_members()
  end

  defp assign_school(socket, school) do
    assign(socket,
      page_title: school.workspace.name,
      school: school,
      events:
        Accounts.list_audit_events(socket.assigns.current_scope,
          workspace_id: school.workspace.id,
          limit: 8
        )
    )
  end

  # The members shown: the search (name, e-mail or phone digits), then the filter.
  defp assign_members(socket) do
    %{school: school, q: q, temp?: temp?} = socket.assigns

    members =
      school.members
      |> Enum.filter(&matches?(&1.user, q))
      |> Enum.filter(&(!temp? or &1.user.must_change_password))
      |> Enum.sort_by(&String.downcase(User.display_name(&1.user)))

    assign(socket,
      members: members,
      temp_count: Enum.count(school.members, & &1.user.must_change_password)
    )
  end

  defp matches?(_user, ""), do: true

  defp matches?(user, q) do
    needle = String.downcase(q)
    digits = String.replace(q, ~r/\D/, "")

    String.contains?(String.downcase(User.display_name(user)), needle) or
      String.contains?(String.downcase(to_string(user.email || "")), needle) or
      (digits != "" and String.contains?(String.replace(user.phone || "", ~r/\D/, ""), digits))
  end

  defp self_path(workspace_id, q, temp?) do
    params =
      Enum.reject([q: String.trim(q), temp: temp? && "1"], fn {_k, v} -> v in [nil, false, ""] end)

    ~p"/admin/schools/#{workspace_id}?#{params}"
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="admin-school" class="space-y-5">
        <.link
          id="school-back"
          navigate={~p"/admin/schools"}
          class="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
        >
          <.icon name="hero-arrow-left" class="size-3.5" />
          {gettext("Établissements")}
        </.link>

        <header class="space-y-2">
          <h1 class="text-2xl font-semibold leading-tight sm:text-[2rem]">
            {@school.workspace.name}
          </h1>
          <p class="flex flex-wrap items-center gap-x-2.5 gap-y-1.5 text-sm text-base-content/70">
            <.school_status
              id="school-verification"
              status={@school.profile.verification_status}
              label={status_label(@school.profile)}
            />
            <span
              :if={@school.workspace.suspended_at}
              id="school-suspended-badge"
              class="inline-flex items-center rounded-full bg-error/15 px-2.5 py-0.5 text-xs font-semibold text-error"
            >
              {gettext("Suspendu : %{reason}", reason: @school.workspace.suspension_reason)}
            </span>
            <span id="school-meta">{meta_line(@school)}</span>
          </p>
        </header>

        <section
          :if={@school.profile.verification_status != :verified}
          id="school-verify"
          class="flex flex-wrap items-center gap-3 rounded-box border border-warning/45 bg-warning/10 px-4 py-3"
        >
          <span class="min-w-0 flex-1 text-sm">
            <span class="block font-semibold">
              {if @school.profile.verification_status == :rejected,
                do:
                  gettext("Rejeté : %{reason}",
                    reason: @school.profile.rejection_reason || "—"
                  ),
                else: gettext("En attente de vérification")}
            </span>
            <span class="text-base-content/70">
              {gettext("Inscrit le %{date}",
                date: Dates.short(DateTime.to_date(@school.profile.inserted_at))
              )}
            </span>
          </span>
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
          <button id="verify-school" type="button" class="btn btn-warning btn-sm" phx-click="verify">
            {gettext("Vérifier")}
          </button>
        </section>

        <div class="grid items-start gap-4 lg:grid-cols-[minmax(0,1fr)_19rem]">
          <section id="school-members-panel" class="flex min-w-0 flex-col gap-3">
            <div class="flex flex-wrap items-center gap-2">
              <h2 class="flex-1 basis-32 text-base font-semibold">
                {gettext("Membres")} · <span class="ta-num">{length(@school.members)}</span>
              </h2>
              <form
                id="member-search"
                phx-change="search"
                phx-submit="search"
                class="w-full sm:w-60"
              >
                <label class="input input-sm w-full">
                  <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
                  <span class="sr-only">{gettext("Rechercher un membre")}</span>
                  <input
                    type="search"
                    name="q"
                    value={@q}
                    placeholder={gettext("Nom ou téléphone")}
                    phx-debounce="300"
                    autocomplete="off"
                  />
                </label>
              </form>
              <.link
                id="filter-temp"
                patch={self_path(@school.workspace.id, @q, !@temp?)}
                aria-pressed={to_string(@temp?)}
                class="ta-pill"
                aria-current={@temp? && "true"}
              >
                {gettext("Mot de passe temporaire")}
                <span class="ta-pill__count ta-num">{@temp_count}</span>
              </.link>
            </div>

            <div class="ta-section overflow-x-auto">
              <p
                :if={@members == []}
                id="members-empty"
                class="px-4 py-6 text-sm text-base-content/70"
              >
                {gettext("Aucun membre ne correspond.")}
              </p>
              <table :if={@members != []} id="school-members" class="table">
                <thead>
                  <tr class="text-xs text-base-content/70">
                    <th class="font-medium">{gettext("Membre")}</th>
                    <th class="hidden font-medium sm:table-cell">{gettext("Rôles")}</th>
                    <th class="font-medium">{gettext("Accès")}</th>
                    <th class="w-12"><span class="sr-only">{gettext("Actions")}</span></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={m <- @members} id={"member-#{m.user_id}"}>
                    <td class="min-w-40">
                      <span class="block font-semibold">{User.display_name(m.user)}</span>
                      <span
                        :if={m.user.name && User.contact(m.user)}
                        class="ta-num block text-xs text-base-content/70"
                      >
                        {User.contact(m.user)}
                      </span>
                      <span class="block text-xs text-base-content/70 sm:hidden">
                        {roles(m.roles)}
                      </span>
                    </td>
                    <td class="hidden text-sm sm:table-cell">{roles(m.roles)}</td>
                    <td class="text-xs">
                      <span :if={m.user.must_change_password} class="font-semibold text-warning">
                        {gettext("Mot de passe temporaire")}
                      </span>
                      <span :if={!m.user.must_change_password && m.user.last_sign_in_at}>
                        {gettext("Connecté le %{date}",
                          date: Dates.day_month(DateTime.to_date(m.user.last_sign_in_at))
                        )}
                      </span>
                      <span
                        :if={!m.user.must_change_password && !m.user.last_sign_in_at}
                        class="text-base-content/70"
                      >
                        {gettext("Jamais connecté")}
                      </span>
                    </td>
                    <td class="text-right">
                      <.action_menu
                        :if={m.user.role != :admin}
                        id={"member-menu-#{m.user_id}"}
                        label={gettext("Actions pour %{name}", name: User.display_name(m.user))}
                      >
                        <:item
                          id={"impersonate-#{m.user_id}"}
                          href={
                            ~p"/impersonation?#{%{user_id: m.user_id, workspace_id: @school.workspace.id}}"
                          }
                          method="post"
                          icon="hero-eye"
                        >
                          {gettext("Ouvrir en tant que")}
                        </:item>
                        <:item
                          id={"reset-user-#{m.user_id}"}
                          click={JS.push("reset_ask", value: %{id: m.user_id})}
                          icon="hero-key"
                        >
                          {gettext("Réinitialiser le mot de passe")}
                        </:item>
                      </.action_menu>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="text-xs text-base-content/70">
              {gettext(
                "Menu ⋯ : ouvrir en tant que (tracé dans le journal), réinitialiser le mot de passe."
              )}
            </p>
          </section>

          <aside class="flex min-w-0 flex-col gap-3">
            <form id="modules-form" phx-submit="save_modules" class="ta-panel flex flex-col gap-1">
              <.panel_title class="pb-1">{gettext("Modules")}</.panel_title>
              <%!-- Posted even when every box is unchecked, so « none » reaches the server. --%>
              <input type="hidden" name="modules[]" value="" />
              <label
                :for={k <- Modules.keys()}
                class="flex min-h-9 cursor-pointer items-center gap-2.5 text-sm"
              >
                <input
                  type="checkbox"
                  id={"module-#{k}"}
                  name="modules[]"
                  value={k}
                  checked={k in @school.workspace.modules}
                  class="checkbox checkbox-sm"
                />
                <span class="flex-1">{Modules.label(k)}</span>
                <span
                  id={"module-use-#{k}"}
                  class={[
                    "ta-num text-[0.7rem]",
                    if((@school.module_use[k] || 0) > 0,
                      do: "text-base-content/70",
                      else: "text-base-content/50"
                    )
                  ]}
                >
                  {module_use(@school.module_use[k])}
                </span>
              </label>
              <button type="submit" class="btn btn-primary btn-sm mt-2 self-start">
                {gettext("Enregistrer")}
              </button>
            </form>

            <section class="ta-panel flex flex-col gap-1.5 text-sm">
              <.panel_title class="pb-1">{gettext("Journal")}</.panel_title>
              <p :if={@events == []} class="text-base-content/70">
                {gettext("Aucune action enregistrée.")}
              </p>
              <ul id="school-events" class="flex flex-col gap-1.5">
                <li :for={e <- @events} id={"event-#{e.id}"}>
                  {AuditEvent.Action.label(e.action)}
                  <span :if={e.target_user}> · {User.display_name(e.target_user)}</span>
                  <span class="text-base-content/70">
                    · {Dates.short_datetime(e.inserted_at)}
                  </span>
                </li>
              </ul>
            </section>

            <section
              id="school-danger"
              class="flex flex-col gap-2.5 rounded-box border border-error/45 p-4"
            >
              <%= if @school.workspace.suspended_at do %>
                <h2 class="text-sm font-semibold text-error">
                  {gettext("Établissement suspendu")}
                </h2>
                <p class="text-sm text-base-content/70">
                  {gettext("Depuis le %{date} : %{reason}",
                    date: Dates.short(DateTime.to_date(@school.workspace.suspended_at)),
                    reason: @school.workspace.suspension_reason
                  )}
                </p>
                <button
                  id="reactivate-school"
                  type="button"
                  class="btn btn-primary btn-sm self-start"
                  phx-click="reactivate"
                >
                  {gettext("Réactiver")}
                </button>
              <% else %>
                <h2 class="text-sm font-semibold text-error">
                  {gettext("Suspendre l'établissement")}
                </h2>
                <p id="suspend-impact" class="text-sm text-base-content/70">
                  {ngettext(
                    "Son membre perd l'accès jusqu'à la levée. Un motif est demandé et tracé.",
                    "Ses %{count} membres perdent l'accès jusqu'à la levée. Un motif est demandé et tracé.",
                    length(@school.members)
                  )}
                </p>
                <button
                  id="suspend-school"
                  type="button"
                  class="btn btn-outline btn-error btn-sm self-start"
                  phx-click="suspend_ask"
                >
                  {gettext("Suspendre…")}
                </button>
              <% end %>
            </section>
          </aside>
        </div>

        <.modal
          :if={@suspend_open?}
          id="suspend-modal"
          title={gettext("Suspendre %{name}", name: @school.workspace.name)}
          on_close="suspend_cancel"
        >
          <form id="suspend-form" phx-submit="suspend" class="space-y-3">
            <p class="text-sm">
              {ngettext(
                "Son membre perd l'accès jusqu'à la levée. Un motif est demandé et tracé.",
                "Ses %{count} membres perdent l'accès jusqu'à la levée. Un motif est demandé et tracé.",
                length(@school.members)
              )}
            </p>
            <label class="fieldset">
              <span class="fieldset-legend">{gettext("Motif de la suspension")}</span>
              <input
                type="text"
                name="reason"
                required
                class="input input-bordered w-full"
                placeholder={gettext("Impayé, demande de l'établissement…")}
              />
            </label>
            <div class="modal-action">
              <button type="button" class="btn btn-ghost" phx-click="suspend_cancel">
                {gettext("Annuler")}
              </button>
              <button id="suspend-confirm" type="submit" class="btn btn-error">
                {gettext("Suspendre")}
              </button>
            </div>
          </form>
        </.modal>

        <.reset_modal :if={@reset_user} user={@reset_user} password={@reset_password} />
      </section>
    </Layouts.app>
    """
  end

  defp status_label(%{verification_status: :verified, verified_at: %DateTime{} = at}),
    do: gettext("Vérifié le %{date}", date: Dates.day_month(DateTime.to_date(at)))

  defp status_label(_profile), do: nil

  # « Lycée technique · Centre · 41 classes · 371 élèves · 56 membres · dernière saisie … »
  defp meta_line(school) do
    Enum.join(
      [
        SchoolType.label(school.profile.school_type),
        CameroonRegion.label(school.profile.region),
        ngettext("%{count} classe", "%{count} classes", school.counts.classes),
        ngettext("%{count} élève", "%{count} élèves", school.counts.students),
        ngettext("%{count} membre", "%{count} membres", school.counts.staff),
        if(school.last_activity,
          do: gettext("dernière saisie %{at}", at: Dates.short_datetime(school.last_activity)),
          else: gettext("aucune saisie")
        )
      ],
      " · "
    )
  end

  defp roles(roles), do: Enum.map_join(roles, ", ", &SchoolRole.label/1)

  defp module_use(nil), do: nil
  defp module_use(0), do: gettext("inutilisé · 30 j")
  defp module_use(n), do: ngettext("%{count} saisie · 30 j", "%{count} saisies · 30 j", n)
end
