defmodule TeacherAssistantWeb.School.ClassLive do
  @moduledoc """
  The class's Élèves tab (spec 2026-10-08 §4): the roster with its filters and
  per-student menu (open, transfer, withdraw), the « Inscrire un élève » drawer
  (a new student with their parent, or a former one re-enrolled) and the class's
  own « Gérer » menu (maximum size, delete).
  """
  use TeacherAssistantWeb, :live_view

  import TeacherAssistantWeb.StudentPhotoComponents, only: [student_avatar: 1]

  import TeacherAssistantWeb.Drawer

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.Sex
  alias TeacherAssistantWeb.School.{ClassShell, EnrollDrawer}
  import ClassShell, only: [class_shell: 1]

  @roster_filters [:all, :f, :m, :repeaters]

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with %{} <- scope.current_workspace,
         {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, id),
         true <- ClassShell.allowed?(scope, cg, :students) || {:elsewhere, cg} do
      {:ok,
       socket
       |> assign(
         cg: cg,
         can_manage_classes?: Enrollment.can_manage_classes?(scope),
         can_manage_guardians?: Enrollment.can_manage_guardians?(scope),
         filter: :all,
         rq: "",
         drawer: nil
       )
       |> load_roster()}
    else
      # Spec 2026-10-08 §3: a viewer who may open another tab of the class lands there.
      {:elsewhere, cg} ->
        case ClassShell.load(scope, cg).tabs do
          [{_tab, path} | _] -> {:ok, push_navigate(socket, to: path)}
          [] -> {:ok, push_navigate(socket, to: ~p"/school")}
        end

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.class_shell cg={@cg} shell={@shell} tab={:students}>
        <:actions>
          <.link
            navigate={~p"/school/bulletins?class=#{@cg.id}"}
            id="go-to-bulletins"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Bulletins")}
          </.link>
          <.link
            :if={@can_manage_classes?}
            navigate={~p"/school/classes/#{@cg.id}/import"}
            id="go-to-import"
            class="btn btn-ghost btn-sm"
          >
            {gettext("Importer une liste")}
          </.link>
          <button
            id="enroll-button"
            type="button"
            class="btn btn-primary btn-sm gap-1.5"
            phx-click="open_enroll"
          >
            <.icon name="hero-plus" class="size-4" /> {gettext("Inscrire un élève")}
          </button>
          <details :if={@can_manage_classes?} id="class-menu" class="dropdown dropdown-end">
            <summary class="btn btn-ghost btn-sm">{gettext("Gérer")} ▾</summary>
            <ul class="menu dropdown-content z-30 mt-1 w-56 rounded-box border border-base-300 bg-base-100 p-1 shadow-lg">
              <li>
                <button id="open-class-settings" type="button" phx-click="open_settings">
                  {gettext("Effectif maximum…")}
                </button>
              </li>
              <li>
                <button
                  id="delete-class"
                  type="button"
                  class="text-error"
                  phx-click="delete_class"
                  data-confirm={gettext("Supprimer la classe %{label} ?", label: @cg.label)}
                >
                  {gettext("Supprimer la classe")}
                </button>
              </li>
            </ul>
          </details>
        </:actions>

        <div
          :if={@roster != []}
          class="flex flex-wrap items-center gap-3 rounded-[0.6rem] border border-base-300 bg-base-100 px-3 py-2.5"
        >
          <form id="roster-search" phx-change="search_roster" class="min-w-48 flex-1">
            <label class="input input-sm w-full">
              <.icon name="hero-magnifying-glass" class="size-4 opacity-60" />
              <input
                type="search"
                name="rq"
                value={@rq}
                phx-debounce="150"
                placeholder={gettext("Nom ou matricule")}
                aria-label={gettext("Rechercher dans la classe")}
              />
            </label>
          </form>
          <div id="roster-filter" role="group" aria-label={gettext("Filtre")} class="flex gap-1">
            <button
              :for={f <- roster_filters()}
              id={"roster-filter-#{f}"}
              type="button"
              phx-click="filter_roster"
              phx-value-filter={f}
              aria-pressed={to_string(@filter == f)}
              class={[
                "rounded-full px-3 py-1 text-sm font-semibold transition-colors",
                if(@filter == f,
                  do: "bg-primary/15 text-primary",
                  else: "text-base-content/70 hover:text-base-content"
                )
              ]}
            >
              {filter_label(f)}
            </button>
          </div>
          <span id="roster-summary" class="ta-num text-xs text-base-content/70">
            {roster_summary(@roster)}
          </span>
        </div>

        <div
          :if={@roster != []}
          class="overflow-x-auto rounded-[0.6rem] border border-base-300 bg-base-100"
        >
          <table id="class-roster" class="table">
            <thead>
              <tr>
                <th class="w-10">{gettext("N°")}</th>
                <th>{gettext("Élève")}</th>
                <th>{gettext("Matricule")}</th>
                <th>{gettext("Né(e) le")}</th>
                <th>{gettext("Parent principal")}</th>
                <th><span class="sr-only">{gettext("Actions")}</span></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={{row, n} <- Enum.with_index(visible_roster(@roster, @filter, @rq), 1)}
                id={"roster-row-#{row.enrollment.id}"}
                class="hover:bg-base-200/60"
              >
                <td class="ta-num text-base-content/60">{n}</td>
                <td>
                  <span class="flex items-center gap-3">
                    <.student_avatar student={row.student} />
                    <span class="min-w-0">
                      <.link
                        navigate={~p"/school/students/#{row.student.id}"}
                        class="block font-semibold hover:text-primary"
                      >
                        {row.student.full_name}
                      </.link>
                      <span class="flex items-center gap-1.5 text-xs text-base-content/60">
                        {row.student.sex && Sex.label(row.student.sex)}
                        <span
                          :if={row.enrollment.repeater}
                          class="rounded bg-warning/20 px-1.5 text-[0.7rem] font-semibold text-warning"
                        >
                          {gettext("Redoublant")}
                        </span>
                      </span>
                    </span>
                  </span>
                </td>
                <td class="ta-num text-sm">{row.student.matricule}</td>
                <td class="ta-num text-sm">{format_date(row.student.birth_date)}</td>
                <td class="text-sm">
                  <%= if guardian = @guardians[row.student.id] do %>
                    <span class="block">{guardian.full_name}</span>
                    <span class="ta-num block text-xs text-base-content/60">{guardian.phone}</span>
                  <% else %>
                    <span class="text-xs font-semibold text-warning">{gettext("Aucun contact")}</span>
                  <% end %>
                </td>
                <td class="text-right">
                  <details id={"row-menu-#{row.enrollment.id}"} class="dropdown dropdown-end">
                    <summary class="btn btn-ghost btn-xs">{gettext("Gérer")} ▾</summary>
                    <ul class="menu dropdown-content z-30 mt-1 w-60 rounded-box border border-base-300 bg-base-100 p-1 text-left shadow-lg">
                      <li>
                        <.link navigate={~p"/school/students/#{row.student.id}"}>
                          {gettext("Ouvrir la fiche")}
                        </.link>
                      </li>
                      <li :if={@transfer_targets != []} class="menu-title text-xs">
                        {gettext("Transférer vers")}
                      </li>
                      <li :for={target <- @transfer_targets}>
                        <button
                          id={"transfer-#{row.enrollment.id}-#{target.id}"}
                          type="button"
                          phx-click="transfer"
                          phx-value-enrollment-id={row.enrollment.id}
                          phx-value-class-id={target.id}
                        >
                          {target.label}
                        </button>
                      </li>
                      <li>
                        <button
                          id={"withdraw-#{row.enrollment.id}"}
                          type="button"
                          class="text-error"
                          phx-click="withdraw"
                          phx-value-enrollment-id={row.enrollment.id}
                          data-confirm={gettext("Retirer cet élève de la classe ?")}
                        >
                          {gettext("Retirer de la classe…")}
                        </button>
                      </li>
                    </ul>
                  </details>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <.empty_state
          :if={@roster == []}
          icon="hero-user-group"
          title={gettext("Aucun élève inscrit")}
        />
      </.class_shell>

      <.live_component
        :if={@drawer == :enroll}
        module={EnrollDrawer}
        id="enroll"
        scope={@current_scope}
        class_group={@cg}
        capacity={@shell.capacity}
        can_manage_guardians?={@can_manage_guardians?}
      />

      <.drawer
        :if={@drawer == :settings}
        id="class-settings-drawer"
        eyebrow={@cg.label}
        title={gettext("Effectif maximum")}
        on_close={JS.push("close_drawer")}
      >
        <form id="class-settings-form" phx-submit="save_settings" class="space-y-2">
          <label for="class-max-size" class="ta-eyebrow block">
            {gettext("Effectif maximum de la classe")}
          </label>
          <.input
            id="class-max-size"
            type="number"
            name="max_size"
            min="1"
            max="200"
            value={@cg.max_size}
            placeholder={school_max_placeholder(@current_scope)}
            class="input input-sm w-full"
          />
          <p class="text-xs text-base-content/60">
            {gettext(
              "Laissez vide pour suivre l'effectif de l'établissement. Alerte au-delà, sans bloquer."
            )}
          </p>
        </form>
        <:footer>
          <button type="button" class="btn btn-ghost btn-sm" phx-click="close_drawer">
            {gettext("Annuler")}
          </button>
          <button type="submit" form="class-settings-form" class="btn btn-primary btn-sm">
            {gettext("Enregistrer")}
          </button>
        </:footer>
      </.drawer>
    </Layouts.app>
    """
  end

  # --- Data -----------------------------------------------------------------------

  defp load_roster(socket) do
    scope = socket.assigns.current_scope
    cg = socket.assigns.cg
    roster = Enrollment.list_roster(scope, cg)

    # A transfer stays within the class's year: a past class has no targets.
    others =
      if cg.academic_year_id == scope.current_academic_year.id,
        do:
          Enrollment.list_class_groups(scope, scope.current_academic_year)
          |> Enum.reject(&(&1.id == cg.id)),
        else: []

    socket
    |> assign(
      roster: roster,
      guardians: Enrollment.primary_guardians(scope, Enum.map(roster, & &1.student.id)),
      # Same level first, then the rest by label.
      transfer_targets: Enum.sort_by(others, &{&1.level != cg.level, &1.label})
    )
    |> ClassShell.assign_shell(count: length(roster))
  end

  defp roster_filters, do: @roster_filters

  defp visible_roster(roster, filter, rq) do
    needle = rq |> String.trim() |> String.downcase()

    Enum.filter(roster, fn %{student: s, enrollment: e} ->
      keep? =
        case filter do
          :all -> true
          :repeaters -> e.repeater
          sex -> s.sex == sex
        end

      keep? and
        (needle == "" or String.contains?(String.downcase(s.full_name), needle) or
           String.contains?(String.downcase(s.matricule || ""), needle))
    end)
  end

  defp roster_summary(roster) do
    f = Enum.count(roster, &(&1.student.sex == :f))
    m = Enum.count(roster, &(&1.student.sex == :m))
    r = Enum.count(roster, & &1.enrollment.repeater)

    Enum.join(
      [
        gettext("%{count} F", count: f),
        gettext("%{count} G", count: m),
        ngettext("%{count} redoublant", "%{count} redoublants", r)
      ],
      " · "
    )
  end

  defp filter_label(:all), do: gettext("Tous")
  defp filter_label(:f), do: gettext("Filles")
  defp filter_label(:m), do: gettext("Garçons")
  defp filter_label(:repeaters), do: gettext("Redoublants")

  defp format_date(nil), do: ""
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  defp school_max_placeholder(scope) do
    case Enrollment.school_max_size(scope) do
      nil -> nil
      n -> to_string(n)
    end
  end

  # --- Events: roster -------------------------------------------------------------

  def handle_event("search_roster", %{"rq" => rq}, socket),
    do: {:noreply, assign(socket, :rq, rq)}

  def handle_event("filter_roster", %{"filter" => f}, socket) do
    {:noreply, assign(socket, :filter, Enum.find(@roster_filters, :all, &(to_string(&1) == f)))}
  end

  def handle_event("transfer", %{"enrollment-id" => eid, "class-id" => cgid}, socket) do
    with %{enrollment: e} <- Enum.find(socket.assigns.roster, &(&1.enrollment.id == eid)),
         %{} = target <- Enum.find(socket.assigns.transfer_targets, &(&1.id == cgid)),
         {:ok, _} <- Enrollment.transfer(socket.assigns.current_scope, e, target) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Élève transféré en %{label}.", label: target.label))
       |> load_roster()}
    else
      {:error, :different_year} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("On ne transfère que vers une classe de la même année.")
         )}

      {:error, error} ->
        {:noreply, Authz.put_failure(socket, error)}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("withdraw", %{"enrollment-id" => eid}, socket) do
    with %{enrollment: e} <- Enum.find(socket.assigns.roster, &(&1.enrollment.id == eid)),
         :ok <- Enrollment.withdraw(socket.assigns.current_scope, e) do
      {:noreply, socket |> put_flash(:info, gettext("Enrollment removed.")) |> load_roster()}
    else
      {:error, error} -> {:noreply, Authz.put_failure(socket, error)}
      nil -> {:noreply, socket}
    end
  end

  # --- Events: drawers ------------------------------------------------------------

  # Everyone on this tab manages the class (form masters included, spec 2026-10-08
  # §3); the enrolment itself is authorised by the resource policies.
  def handle_event("open_enroll", _params, socket),
    do: {:noreply, assign(socket, :drawer, :enroll)}

  def handle_event("close_drawer", _params, socket), do: {:noreply, assign(socket, :drawer, nil)}

  # --- Events: the class ----------------------------------------------------------

  def handle_event("open_settings", _params, socket) when socket.assigns.can_manage_classes?,
    do: {:noreply, assign(socket, :drawer, :settings)}

  def handle_event("save_settings", %{"max_size" => raw}, socket)
      when socket.assigns.can_manage_classes? do
    with {:ok, value} <- parse_max_size(raw),
         {:ok, cg} <-
           Enrollment.set_class_max_size(socket.assigns.current_scope, socket.assigns.cg, value) do
      {:noreply,
       socket
       |> assign(cg: cg, drawer: nil)
       |> ClassShell.assign_shell(count: length(socket.assigns.roster))
       |> put_flash(:info, gettext("Effectif maximum enregistré."))}
    else
      :invalid ->
        {:noreply, put_flash(socket, :error, gettext("Entrez un nombre entre 1 et 200."))}

      {:error, error} ->
        {:noreply, Authz.put_failure(socket, error)}
    end
  end

  def handle_event("delete_class", _params, socket) when socket.assigns.can_manage_classes? do
    case Enrollment.delete_class_group(socket.assigns.current_scope, socket.assigns.cg) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Class deleted."))
         |> push_navigate(to: ~p"/school/classes")}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, :has_data} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("This class has students or teachers — remove them first.")
         )}

      {:error, error} ->
        {:noreply, Authz.put_failure(socket, error)}
    end
  end

  def handle_event(event, _params, socket)
      when event in ["open_settings", "save_settings", "delete_class"],
      do: {:noreply, socket}

  # Empty: follow the school's maximum.
  defp parse_max_size(raw), do: raw |> String.trim() |> max_size_value()

  defp max_size_value(""), do: {:ok, nil}

  defp max_size_value(text) do
    case Integer.parse(text) do
      {n, ""} when n in 1..200 -> {:ok, n}
      _ -> :invalid
    end
  end

  # --- Enrolment ------------------------------------------------------------------

  def handle_info({EnrollDrawer, {:enrolled, _cg, then}}, socket) do
    socket = load_roster(socket)

    {:noreply,
     socket
     |> put_flash(
       :info,
       EnrollDrawer.enrolled_message(socket.assigns.cg, socket.assigns.shell.capacity)
     )
     |> assign(:drawer, if(then == :another, do: :enroll, else: nil))}
  end

  def handle_info({EnrollDrawer, {:reenrolled, _cg}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, gettext("Student re-enrolled."))
     |> assign(drawer: nil)
     |> load_roster()}
  end

  def handle_info({EnrollDrawer, :forbidden}, socket),
    do: {:noreply, Authz.put_not_allowed(socket)}
end
