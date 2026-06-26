defmodule TeacherAssistantWeb.Teacher.DashboardLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    workspace = scope.current_workspace
    academic_year = scope.current_academic_year

    assigns =
      if academic_year do
        Academics.dashboard_metrics(workspace)
      else
        %{academic_year: nil, classrooms_count: 0, recent_attendance: [], lesson_entries: []}
      end

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="teacher-dashboard" class="space-y-6">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p class="ta-section-label">{gettext("Teacher desk")}</p>
            <h1 class="text-3xl font-semibold tracking-normal">{gettext("Teacher dashboard")}</h1>
            <p class="mt-2 max-w-2xl text-sm leading-6 text-base-content/65">
              {gettext(
                "Manage your personal classes, roll call, and lesson progress for the active academic year."
              )}
            </p>
          </div>
          <.link navigate={~p"/teacher/classrooms"} class="btn btn-primary">
            <.icon name="hero-plus" class="size-5" />
            {gettext("Add classroom")}
          </.link>
        </div>

        <div
          :if={!@academic_year}
          id="academic-year-setup-gate"
          class="ta-panel flex flex-col gap-4 p-6 sm:flex-row sm:items-center sm:justify-between"
        >
          <div>
            <h2 class="text-lg font-semibold">{gettext("Set up your academic year")}</h2>
            <p class="mt-1 text-sm text-base-content/65">
              {gettext(
                "Your classrooms, roll calls, and progress entries need a current academic year."
              )}
            </p>
          </div>
          <.link navigate={~p"/teacher/setup"} class="btn btn-primary">
            <.icon name="hero-calendar" class="size-5" />
            {gettext("Create academic year")}
          </.link>
        </div>

        <div :if={@academic_year} id="dashboard-summary" class="grid gap-4 md:grid-cols-3">
          <div class="ta-kpi">
            <div class="text-xs font-semibold uppercase text-base-content/50">
              {gettext("Academic year")}
            </div>
            <div class="mt-2 text-2xl font-semibold">{@academic_year.name}</div>
          </div>
          <div class="ta-kpi">
            <div class="text-xs font-semibold uppercase text-base-content/50">
              {gettext("Classrooms")}
            </div>
            <div class="mt-2 text-2xl font-semibold">{@classrooms_count}</div>
          </div>
          <div class="ta-kpi">
            <div class="text-xs font-semibold uppercase text-base-content/50">
              {gettext("Planned lessons")}
            </div>
            <div class="mt-2 text-2xl font-semibold">{length(@lesson_entries)}</div>
          </div>
        </div>

        <div :if={@academic_year} class="grid gap-5 lg:grid-cols-2">
          <section id="recent-roll-calls" class="ta-panel p-5">
            <h2 class="font-semibold">{gettext("Recent roll calls")}</h2>
            <div class="mt-4 overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>{gettext("Date")}</th>
                    <th>{gettext("Classroom")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@recent_attendance == []}>
                    <td colspan="2" class="text-base-content/55">
                      {gettext("No roll calls yet.")}
                    </td>
                  </tr>
                  <tr :for={session <- @recent_attendance} id={"attendance-session-#{session.id}"}>
                    <td>{Calendar.strftime(session.date, "%d %b %Y")}</td>
                    <td>
                      {session.personal_classroom.class_label} · {session.personal_classroom.subject}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>

          <section id="recent-progress" class="ta-panel p-5">
            <h2 class="font-semibold">{gettext("Lesson progress")}</h2>
            <div class="mt-4 overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>{gettext("Planned")}</th>
                    <th>{gettext("Lesson")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@lesson_entries == []}>
                    <td colspan="2" class="text-base-content/55">
                      {gettext("No planned lessons yet.")}
                    </td>
                  </tr>
                  <tr :for={entry <- @lesson_entries} id={"lesson-entry-#{entry.id}"}>
                    <td>{Calendar.strftime(entry.planned_on, "%d %b")}</td>
                    <td>{entry.title}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
