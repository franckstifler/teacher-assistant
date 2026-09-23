defmodule TeacherAssistantWeb.School.CoursesLive do
  @moduledoc """
  "Mes cours": the signed-in teacher's assignments in the current school,
  one row per solo assignment or combined course, each linking to the
  roster, marks, results and today's roll call. The landing page for
  members who are neither admins nor form masters.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Academics.CombinedCourse

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace_type == :school do
      units = Curriculum.list_units_for_scope(scope)

      first_lesson =
        scope.current_workspace
        |> Attendance.list_periods()
        |> Enum.find(&(&1.kind == :lesson))

      {:ok,
       socket
       |> assign(:courses, Enum.map(units, &course_row(&1, first_lesson)))
       |> assign(:today, Date.utc_today())}
    else
      {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  # One row per unit. A combined course lists every member class; the marks
  # and roster pages take any member context id (they resolve the course).
  defp course_row({:course, %CombinedCourse{} = course} = unit, first_lesson) do
    contexts = course.id |> Curriculum.contexts_of_course!() |> Ash.load!(:class_group)
    representative = List.first(contexts)

    %{
      id: Curriculum.unit_select_id(unit),
      label: course.label,
      subject: course.subject,
      classes: Enum.map(contexts, & &1.class_group),
      context_id: representative.id,
      attendance_class_id: representative.class_group_id,
      first_lesson: first_lesson
    }
  end

  defp course_row({:solo, ctx} = unit, first_lesson) do
    %{
      id: Curriculum.unit_select_id(unit),
      label: Curriculum.unit_label(unit),
      subject: ctx.subject,
      classes: [ctx.class_group],
      context_id: ctx.id,
      attendance_class_id: ctx.class_group_id,
      first_lesson: first_lesson
    }
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="courses" class="mx-auto max-w-3xl space-y-4">
        <.page_header eyebrow={gettext("Enseignement")} title={gettext("Mes cours")} />

        <div :if={@courses == []} id="courses-empty">
          <.empty_state
            icon="hero-academic-cap"
            title={gettext("Aucun cours attribué")}
            message={
              gettext(
                "Un administrateur de l'établissement doit vous attribuer une matière dans une classe."
              )
            }
          />
        </div>

        <ul :if={@courses != []} class="space-y-3">
          <li :for={course <- @courses} id={"course-#{course.id}"} class="ta-leaf p-4">
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <h2 class="text-base font-semibold ta-display">{course.label}</h2>
              <p class="text-sm text-base-content/70">
                {course.subject} ·
                <span :for={cg <- course.classes} class="badge badge-ghost badge-sm mr-1">
                  {cg.label}
                </span>
              </p>
            </div>
            <div class="mt-3 flex flex-wrap gap-2">
              <.link
                navigate={~p"/teacher/contexts/#{course.context_id}/roster"}
                class="btn btn-ghost btn-sm gap-2"
              >
                <.icon name="hero-user-group" class="size-4" /> {gettext("Élèves")}
              </.link>
              <.link
                navigate={~p"/teacher/contexts/#{course.context_id}/marks"}
                class="btn btn-primary btn-sm gap-2"
              >
                <.icon name="hero-pencil-square" class="size-4" /> {gettext("Notes")}
              </.link>
              <.link
                navigate={~p"/teacher/contexts/#{course.context_id}/marks/summary"}
                class="btn btn-ghost btn-sm gap-2"
              >
                <.icon name="hero-trophy" class="size-4" /> {gettext("Résultats")}
              </.link>
              <.link
                :if={course.first_lesson}
                navigate={
                  ~p"/school/classes/#{course.attendance_class_id}/attendance/#{course.first_lesson.id}?date=#{Date.to_iso8601(@today)}"
                }
                class="btn btn-ghost btn-sm gap-2"
              >
                <.icon name="hero-clipboard-document-check" class="size-4" /> {gettext("Appel")}
              </.link>
            </div>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
