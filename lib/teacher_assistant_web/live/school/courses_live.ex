defmodule TeacherAssistantWeb.School.CoursesLive do
  @moduledoc """
  "Mes cours": the signed-in teacher's assignments in the current school,
  one row per solo assignment or combined course, each linking to the
  roster, marks, results and today's roll call. The landing page for
  members who are neither admins nor form masters.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Assessment, Attendance, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.Timetabling

  alias TeacherAssistant.Academics.{
    CoefficientRules,
    CombinedCourse,
    EntryProgress,
    Lock,
    Reference
  }

  alias TeacherAssistantWeb.Dates

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_workspace != nil do
      today = Date.utc_today()
      units = scope |> Curriculum.list_units_for_scope() |> Enum.map(&with_contexts(&1, scope))
      contexts = Enum.flat_map(units, &elem(&1, 1))
      seq = current_sequence(scope)

      lessons =
        scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

      ctx = %{
        today: today,
        day: day_of_week(today),
        lessons: lessons,
        own_slots: Timetabling.teacher_timetable(scope, scope.current_user),
        scope: scope,
        user_id: scope.current_user.id,
        coefficients: Curriculum.coefficient_cells(scope),
        progress: progress(scope, seq, contexts),
        students: student_counts(scope, contexts)
      }

      courses = Enum.map(units, &course_row(&1, ctx))

      {:ok,
       socket
       |> assign(:courses, courses)
       |> assign(:seq, seq)
       # Each class once, even when the teacher has it in two subjects.
       |> assign(:student_total, ctx.students |> Map.values() |> Enum.sum())
       |> assign(:today, today)}
    else
      {:ok, push_navigate(socket, to: ~p"/school")}
    end
  end

  # Every unit with its member contexts (and their class), loaded once.
  defp with_contexts({:course, %CombinedCourse{} = course} = unit, scope) do
    contexts =
      course.id
      |> Curriculum.contexts_of_course!(scope: scope)
      # `:class_group` is also multitenant — Ash needs a scope to resolve the load.
      |> Ash.load!(:class_group, scope: scope)

    {unit, contexts}
  end

  defp with_contexts({:solo, tc} = unit, _scope), do: {unit, [tc]}

  defp current_sequence(%{current_academic_year: nil}), do: nil

  defp current_sequence(%{current_academic_year: year} = scope),
    do:
      scope |> Organization.list_sequences(year) |> Assessment.default_sequence(Reference.today())

  defp progress(_scope, nil, _contexts), do: %{}

  defp progress(scope, seq, contexts),
    do: EntryProgress.context_cells(scope, scope.current_academic_year, seq, contexts)

  defp student_counts(scope, contexts) do
    contexts
    |> Enum.map(& &1.class_group)
    |> Enum.uniq_by(& &1.id)
    |> Map.new(&{&1.id, length(Enrollment.list_students(scope, &1))})
  end

  # One row per unit. A combined course lists every member class; the marks
  # and roster pages take any member context id (they resolve the course).
  defp course_row({{:course, %CombinedCourse{} = course}, contexts}, ctx) do
    representative = List.first(contexts)

    Map.merge(facts(contexts, ctx), %{
      id: "combined-#{course.id}",
      label: course.label,
      subject: course.subject,
      context_id: representative.id,
      attendance_class_id: representative.class_group_id,
      roll_call_period: roll_call_period(representative.class_group, ctx)
    })
  end

  defp course_row({{:solo, tc} = unit, contexts}, ctx) do
    Map.merge(facts(contexts, ctx), %{
      id: tc.id,
      label: Curriculum.unit_label(unit),
      subject: tc.subject,
      context_id: tc.id,
      attendance_class_id: tc.class_group_id,
      roll_call_period: roll_call_period(tc.class_group, ctx)
    })
  end

  # Card facts over the member contexts: students, coefficient (first member's grid
  # cell), form master, séquence entry progress.
  defp facts([first | _] = contexts, ctx) do
    classes = Enum.map(contexts, & &1.class_group)
    cells = Enum.map(contexts, &Map.get(ctx.progress, &1.id, %{entered: 0, expected: 0}))
    entered = cells |> Enum.map(& &1.entered) |> Enum.sum()
    expected = cells |> Enum.map(& &1.expected) |> Enum.sum()

    %{
      classes: classes,
      students: classes |> Enum.map(&Map.get(ctx.students, &1.id, 0)) |> Enum.sum(),
      coefficient: coefficient(ctx.coefficients, first),
      pp?: Enum.any?(classes, &(&1.form_master_user_id == ctx.user_id)),
      progress: %{entered: entered, expected: expected, pct: EntryProgress.pct(entered, expected)}
    }
  end

  defp coefficient(_cells, %{subject_id: nil}), do: nil

  defp coefficient(cells, %{subject_id: subject_id, class_group: cg}) do
    key = %{subject_id: subject_id, subsystem: cg.subsystem, level: cg.level, serie: cg.serie}

    case CoefficientRules.resolve(cells, key) do
      nil -> nil
      found -> cells[found].coefficient
    end
  end

  defp coef_label(%Decimal{} = d),
    do: d |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")

  defp coef_label(n), do: to_string(n)

  defp progress_tone(%{expected: 0}), do: "bg-base-300"
  defp progress_tone(%{pct: 100}), do: "bg-primary"
  defp progress_tone(%{entered: 0}), do: "bg-error"
  defp progress_tone(_progress), do: "bg-warning"

  defp subtitle(courses, students, seq) do
    base =
      ngettext("%{count} cours", "%{count} cours", length(courses)) <>
        " · " <> ngettext("%{count} élève", "%{count} élèves", students)

    if seq && not Lock.locked?(seq) do
      base <>
        " · " <>
        gettext("Séquence %{n} ouverte jusqu'au %{date}",
          n: seq.number,
          date: Dates.day_month(seq.grade_entry_deadline)
        )
    else
      base
    end
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
        own_slots |> Map.get({day, p.id}, []) |> Enum.any?(&(&1.class_group_id == class_group.id))
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
      <section id="courses" class="space-y-4">
        <.page_header
          eyebrow={
            if @current_scope.current_academic_year,
              do: gettext("Enseignement") <> " · " <> @current_scope.current_academic_year.name,
              else: gettext("Enseignement")
          }
          title={gettext("Mes cours")}
          subtitle={@courses != [] && subtitle(@courses, @student_total, @seq)}
        />

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

        <ul
          :if={@courses != []}
          class="grid gap-3 [grid-template-columns:repeat(auto-fill,minmax(270px,1fr))]"
        >
          <li
            :for={course <- @courses}
            id={"course-#{course.id}"}
            class="ta-leaf flex flex-col gap-3 p-4 transition hover:-translate-y-0.5 hover:shadow-md"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <h2 class="font-display text-2xl leading-tight">
                  <%= if length(course.classes) > 1 do %>
                    {course.label}
                  <% else %>
                    {hd(course.classes).label}
                  <% end %>
                </h2>
                <p class="mt-0.5 text-sm text-base-content/70">
                  {course.subject} · {ngettext("%{count} élève", "%{count} élèves", course.students)}
                  <span :if={course.coefficient}>
                    · {gettext("coef. %{n}", n: coef_label(course.coefficient))}
                  </span>
                </p>
                <p :if={length(course.classes) > 1} class="mt-1 flex flex-wrap gap-1">
                  <span :for={cg <- course.classes} class="badge badge-ghost badge-sm">
                    {cg.label}
                  </span>
                </p>
              </div>
              <span
                :if={course.pp?}
                data-role="pp"
                title={gettext("Professeur principal")}
                class="badge badge-sm border-0 bg-warning/20 font-semibold text-warning"
              >
                PP
              </span>
            </div>

            <div :if={@seq} data-role="progress" class="space-y-1">
              <div class="flex items-baseline justify-between text-xs">
                <span class="text-base-content/70">
                  {gettext("Notes Séq. %{n}", n: @seq.number)}
                </span>
                <span :if={course.progress.expected > 0} class="ta-num font-semibold">
                  {course.progress.entered} / {course.progress.expected}
                </span>
                <span :if={course.progress.expected == 0} class="text-base-content/60">
                  {gettext("aucune évaluation")}
                </span>
              </div>
              <div class="h-1.5 overflow-hidden rounded-full bg-base-300">
                <div
                  class={["h-full rounded-full transition-all", progress_tone(course.progress)]}
                  style={"width: #{course.progress.pct || 0}%"}
                >
                </div>
              </div>
            </div>

            <div class="mt-auto grid grid-cols-4 gap-1.5">
              <.link
                navigate={~p"/teacher/contexts/#{course.context_id}/marks"}
                class="btn btn-primary btn-sm px-1"
              >
                {gettext("Notes")}
              </.link>
              <.link
                :if={course.roll_call_period}
                navigate={
                  ~p"/school/classes/#{course.attendance_class_id}/attendance/#{course.roll_call_period.id}?date=#{Date.to_iso8601(@today)}"
                }
                class="btn btn-outline btn-sm px-1"
              >
                {gettext("Appel")}
              </.link>
              <span :if={!course.roll_call_period} class="btn btn-outline btn-sm btn-disabled px-1">
                {gettext("Appel")}
              </span>
              <.link
                navigate={~p"/teacher/contexts/#{course.context_id}/marks/summary"}
                class="btn btn-outline btn-sm px-1"
              >
                {gettext("Résultats")}
              </.link>
              <.link
                navigate={~p"/teacher/contexts/#{course.context_id}/roster"}
                class="btn btn-outline btn-sm px-1"
              >
                {gettext("Élèves")}
              </.link>
            </div>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
