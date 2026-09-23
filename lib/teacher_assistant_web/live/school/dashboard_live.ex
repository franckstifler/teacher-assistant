defmodule TeacherAssistantWeb.School.DashboardLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Accounts

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace_type == :school do
      {:ok,
       socket
       |> assign(:scope, scope)
       |> load_stats()}
    else
      {:ok, push_navigate(socket, to: ~p"/teacher")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="school-dashboard" class="flex flex-col gap-6">
        <.page_header eyebrow={gettext("École")} title={@current_scope.current_workspace.name}>
          <:actions :if={@year}>
            <span class="ta-num inline-flex items-center rounded-md border border-base-300 bg-base-100 px-3 py-1.5 text-xs font-semibold text-base-content/70">
              {@year.name}
            </span>
          </:actions>
        </.page_header>

        <%!-- Verification gate callout (mockup: the amber "réglages bloquent" alert) —
             preserved exactly: real school_verification_status, no data invented --%>
        <div
          :if={@current_scope.school_verification_status != :verified}
          id="pending-verification"
          class="ta-leaf flex gap-3 border-l-4 border-warning"
        >
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-warning" />
          <p class="text-sm leading-relaxed text-base-content/80">
            {gettext(
              "Votre établissement est configuré mais pas encore vérifié. Vous pouvez préparer classes et personnel ; la saisie des notes, de l'appel et des bulletins sera débloquée après vérification."
            )}
          </p>
        </div>

        <%!-- Onboarding checklist (mockup: "À traiter cette semaine" card) — every
             row here reflects a real computed assign, no invented items --%>
        <div id="setup-checklist" class="ta-leaf space-y-2">
          <h2 class="ta-eyebrow">{gettext("Mise en route")}</h2>
          <ul class="divide-y divide-base-300/70 text-sm">
            <li
              id="setup-checklist-profile"
              class="flex items-center gap-2 py-1.5 first:pt-0 last:pb-0"
            >
              <.icon
                name={if @profile_complete?, do: "hero-check-circle", else: "hero-x-circle"}
                class={"size-4 shrink-0 " <> if(@profile_complete?, do: "text-primary", else: "text-base-content/40")}
              />
              {gettext("Profil de l'établissement")}
            </li>
            <li id="setup-checklist-year" class="flex items-center gap-2 py-1.5 first:pt-0 last:pb-0">
              <.icon
                name={if @year != nil, do: "hero-check-circle", else: "hero-x-circle"}
                class={"size-4 shrink-0 " <> if(@year != nil, do: "text-primary", else: "text-base-content/40")}
              />
              {gettext("Année scolaire")}
            </li>
            <li
              id="setup-checklist-classes"
              class="flex items-center gap-2 py-1.5 first:pt-0 last:pb-0"
            >
              <.icon
                name={if @classes != [], do: "hero-check-circle", else: "hero-x-circle"}
                class={"size-4 shrink-0 " <> if(@classes != [], do: "text-primary", else: "text-base-content/40")}
              />
              {gettext("Classes")}
            </li>
            <li id="setup-checklist-staff" class="flex items-center gap-2 py-1.5 first:pt-0 last:pb-0">
              <.icon
                name={if @staff_count > 1, do: "hero-check-circle", else: "hero-x-circle"}
                class={"size-4 shrink-0 " <> if(@staff_count > 1, do: "text-primary", else: "text-base-content/40")}
              />
              {gettext("Personnel")}
            </li>
          </ul>
        </div>

        <%!-- KPI strip (mockup: the row of stat cards) — Classes/Students/
             Teachers are the only school-wide numbers this LiveView actually
             computes; a programme-coverage or fees KPI is not (yet) wired
             to any query, so it's omitted rather than invented.

             The `:require_school_setup` on_mount gate redirects to
             /school/setup before this LiveView mounts unless the school
             already has an active year and at least one class, so the
             KPI strip is always reachable here. --%>
        <div id="dashboard-stats" class="grid grid-cols-3 gap-2 sm:gap-3">
          <.stat label={gettext("Classes")} value={Integer.to_string(@classes_count)} />
          <.stat
            label={gettext("Students")}
            value={Integer.to_string(@students_count)}
            tone={:primary}
          />
          <.stat label={gettext("Teachers")} value={Integer.to_string(@teachers_count)} />
        </div>

        <%!-- "Mes classes" — the classes this head teacher also form-masters
             (mockup: the "Classes & élèves" list, trimmed to real fields) --%>
        <div :if={@my_classes != []} id="my-classes" class="ta-leaf space-y-2">
          <div class="flex items-center justify-between gap-3">
            <h2 class="ta-eyebrow">{gettext("Mes classes")}</h2>
            <span class="ta-num text-xs text-base-content/60">
              {ngettext("%{count} classe", "%{count} classes", length(@my_classes),
                count: length(@my_classes)
              )}
            </span>
          </div>
          <ul class="divide-y divide-base-300/70 text-sm">
            <li :for={c <- @my_classes} class="py-1.5 first:pt-0 last:pb-0">
              <.link
                navigate={~p"/school/classes/#{c.id}"}
                class="flex items-center justify-between gap-3 font-semibold hover:text-primary hover:no-underline"
              >
                <span class="truncate">{c.label}</span>
                <span class="ta-num shrink-0 text-xs font-normal text-base-content/60">
                  {c.level}
                </span>
              </.link>
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp load_stats(socket) do
    scope = socket.assigns.current_scope
    year = scope.current_academic_year

    classes =
      if year, do: Enrollment.list_class_groups(scope.current_workspace, year), else: []

    students_count =
      classes
      |> Enum.map(&length(Enrollment.list_roster(&1)))
      |> Enum.sum()

    teachers_count =
      classes
      |> Enum.flat_map(&Curriculum.list_assignments_for_class(&1))
      |> Enum.map(& &1.teacher_user_id)
      |> Enum.uniq()
      |> length()

    my_classes =
      if year,
        do:
          Enrollment.list_form_master_classes(scope.current_workspace, scope.current_user, year),
        else: []

    profile_complete? =
      case Accounts.fetch_school_profile(scope.current_workspace) do
        {:ok, profile} -> profile.head_name not in [nil, ""]
        _ -> false
      end

    staff_count = scope.current_workspace |> Accounts.list_members() |> length()

    socket
    |> assign(:year, year)
    |> assign(:classes, classes)
    |> assign(:classes_count, length(classes))
    |> assign(:students_count, students_count)
    |> assign(:teachers_count, teachers_count)
    |> assign(:my_classes, my_classes)
    |> assign(:profile_complete?, profile_complete?)
    |> assign(:staff_count, staff_count)
  end
end
