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
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Academics.CombinedCourse

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil do
      today = Date.utc_today()
      units = Curriculum.list_units_for_scope(scope)

      lessons =
        scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

      own_slots = Timetabling.teacher_timetable(scope, scope.current_user)

      ctx = %{
        today: today,
        day: day_of_week(today),
        lessons: lessons,
        own_slots: own_slots,
        scope: scope
      }

      {:ok,
       socket
       |> assign(:courses, Enum.map(units, &course_row(&1, ctx)))
       |> assign(:today, today)}
    else
      {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  # One row per unit. A combined course lists every member class; the marks
  # and roster pages take any member context id (they resolve the course).
  defp course_row({:course, %CombinedCourse{} = course}, ctx) do
    contexts =
      course.id
      |> Curriculum.contexts_of_course!(scope: ctx.scope)
      # `:class_group` is also multitenant — Ash needs a scope to resolve the load.
      |> Ash.load!(:class_group, scope: ctx.scope)

    representative = List.first(contexts)

    %{
      id: "combined-#{course.id}",
      label: course.label,
      subject: course.subject,
      classes: Enum.map(contexts, & &1.class_group),
      context_id: representative.id,
      attendance_class_id: representative.class_group_id,
      roll_call_period: roll_call_period(representative.class_group, ctx)
    }
  end

  defp course_row({:solo, tc} = unit, ctx) do
    %{
      id: tc.id,
      label: Curriculum.unit_label(unit),
      subject: nil,
      classes: [tc.class_group],
      context_id: tc.id,
      attendance_class_id: tc.class_group_id,
      roll_call_period: roll_call_period(tc.class_group, ctx)
    }
  end

  # Today's roll call target for a class: the teacher's own slot on today's
  # weekday when the timetable has one, otherwise the first lesson period the
  # class has nothing placed on (assignment-based roll call), otherwise the
  # first lesson period.
  defp roll_call_period(_class_group, %{lessons: []}), do: nil
  defp roll_call_period(_class_group, %{day: nil, lessons: [first | _]}), do: first

  defp roll_call_period(class_group, %{day: day, lessons: lessons, own_slots: own_slots} = ctx) do
    own =
      Enum.find(lessons, fn p ->
        match?(%{class_group_id: id} when id == class_group.id, Map.get(own_slots, {day, p.id}))
      end)

    own || first_free_lesson(ctx.scope, class_group, day, lessons) || List.first(lessons)
  end

  defp first_free_lesson(scope, class_group, day, lessons) do
    %{slots: grid} = Timetabling.class_timetable(scope, class_group)
    Enum.find(lessons, &(not Map.has_key?(grid, {day, &1.id})))
  end

  defp day_of_week(date) do
    case Date.day_of_week(date) do
      7 -> nil
      n -> Enum.at([:monday, :tuesday, :wednesday, :thursday, :friday, :saturday], n - 1)
    end
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
                <span :if={course.subject}>{course.subject} · </span>
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
                :if={course.roll_call_period}
                navigate={
                  ~p"/school/classes/#{course.attendance_class_id}/attendance/#{course.roll_call_period.id}?date=#{Date.to_iso8601(@today)}"
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
