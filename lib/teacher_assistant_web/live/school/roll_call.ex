defmodule TeacherAssistantWeb.School.RollCall do
  @moduledoc """
  One roll call (class × period × date) as plain state, shared by the roll-call
  page (`AttendanceLive`) and the teacher's day (`MyDayLive`): resolve and
  authorize it, toggle a student, record it, and render it as the mockup's panel.

  The roll starts with every student present (the cahier d'appel default); the
  teacher only taps the absent and late few. `taken?` tells "all present" apart
  from "not done yet".
  """
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.{Attendance, Curriculum, Discipline, Enrollment, Scope}
  alias TeacherAssistant.Academics.{AttendanceStatus, CombinedCourse, TeachingContext}
  alias TeacherAssistant.Academics.TimetableSlot

  @statuses [:present, :absent, :late]
  @valid_statuses Map.new(@statuses, &{Atom.to_string(&1), &1})

  @doc """
  Opens the roll call of class `cg_id` at `period_id` on `date`: `{:ok, roll}`,
  `{:error, :not_found}` or `{:error, :forbidden}` (neither the course's teacher
  nor a conduct manager).
  """
  def open(%Scope{} = scope, cg_id, period_id, %Date{} = date) do
    with {:ok, cg} <- Enrollment.fetch_owned_class_group(scope, cg_id),
         {:ok, period} <- fetch_period(scope, period_id) do
      slot = slot(scope, cg, date, period.id)
      teaching_context = resolve_teaching_context(scope, cg, slot)

      if authorized?(scope, teaching_context) do
        roll = %{
          cg: cg,
          period: period,
          date: date,
          teaching_context: teaching_context,
          course: combined_course_for(scope, teaching_context)
        }

        {:ok, reload(scope, roll)}
      else
        {:error, :forbidden}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Sets one student's status (`\"present\" | \"absent\" | \"late\"`); unknown ids or statuses are ignored."
  def set(roll, enrollment_id, status) do
    status = Map.get(@valid_statuses, status)

    if status && Enum.any?(roll.students, &(&1.enrollment_id == enrollment_id)),
      do: put_in(roll, [:marks, enrollment_id], status),
      else: roll
  end

  @doc "Records the roll: `{:ok, roll}` (reloaded) or `{:error, :unverified | :forbidden | :failed}`."
  def record(%Scope{} = scope, roll) do
    cond do
      not Scope.school_verified?(scope) ->
        {:error, :unverified}

      not authorized?(scope, roll.teaching_context) ->
        {:error, :forbidden}

      true ->
        marks =
          Enum.map(roll.students, &{&1.enrollment_id, Map.fetch!(roll.marks, &1.enrollment_id)})

        case write(scope, roll, marks) do
          {:ok, _count} -> {:ok, reload(scope, roll)}
          {:error, %Ash.Error.Forbidden{}} -> {:error, :forbidden}
          {:error, _reason} -> {:error, :failed}
        end
    end
  end

  @doc "Flashes why `record/2` failed."
  def put_error(socket, :forbidden), do: TeacherAssistantWeb.Authz.put_not_allowed(socket)

  def put_error(socket, :unverified),
    do:
      Phoenix.LiveView.put_flash(
        socket,
        :error,
        gettext("École en attente de vérification — enregistrement indisponible.")
      )

  def put_error(socket, :failed),
    do: Phoenix.LiveView.put_flash(socket, :error, gettext("Impossible d'enregistrer l'appel"))

  def count(roll, status), do: Enum.count(roll.marks, fn {_id, s} -> s == status end)

  # --- loading -----------------------------------------------------------------

  defp reload(scope, %{course: %CombinedCourse{} = course} = roll) do
    groups = Attendance.combined_period_roll(scope, course, roll.period, roll.date)
    students = Enum.flat_map(groups, & &1.students)
    put_students(roll, students, groups: groups, flags: %{})
  end

  defp reload(scope, roll) do
    %{students: students} = Attendance.period_roll(scope, roll.cg, roll.period, roll.date)
    put_students(roll, students, groups: nil, flags: earlier_absences(scope, roll))
  end

  defp put_students(roll, students, extra) do
    Map.merge(roll, %{
      students: Enum.map(students, &Map.take(&1, [:enrollment_id, :student_name])),
      marks: Map.new(students, &{&1.enrollment_id, &1.status || :present}),
      taken?: Enum.any?(students, &(&1.status != nil)),
      groups: extra[:groups],
      flags: extra[:flags]
    })
  end

  # Students marked absent at an earlier lesson period the same day — the
  # mockup's "absent au créneau précédent" signal. `enrollment_id => [label]`.
  defp earlier_absences(scope, roll) do
    %{periods: periods, students: students} = Attendance.class_register(scope, roll.cg, roll.date)
    earlier = Enum.filter(periods, &(&1.position < roll.period.position))

    Map.new(students, fn s ->
      {s.enrollment_id, for(p <- earlier, s.cells[p.id] == :absent, do: p)}
    end)
  end

  defp write(scope, %{course: %CombinedCourse{} = course} = roll, marks),
    do: Attendance.record_combined_period(scope, course, roll.period, roll.date, marks)

  defp write(scope, roll, marks),
    do:
      Attendance.record_period(
        scope,
        roll.cg,
        roll.period,
        roll.teaching_context,
        roll.date,
        marks
      )

  defp fetch_period(scope, period_id) do
    case Enum.find(Attendance.list_periods(scope), &(&1.id == period_id)) do
      nil -> {:error, :not_found}
      period -> {:ok, period}
    end
  end

  defp slot(scope, cg, date, period_id) do
    case Attendance.slot_for(scope, cg, date, period_id) do
      {:ok, slot} -> slot
      {:error, :no_slot} -> nil
    end
  end

  # The teaching context this roll call is recorded under: the placed timetable
  # slot's when one exists, otherwise the signed-in teacher's own assignment on
  # the class (assignment-based roll call). `nil` when neither applies (a
  # conduct manager can still record without one).
  defp resolve_teaching_context(_scope, _cg, %TimetableSlot{teaching_context: ctx}), do: ctx

  defp resolve_teaching_context(scope, cg, nil) do
    case {scope.current_workspace, scope.current_academic_year} do
      {%{}, %{} = year} ->
        scope
        |> Curriculum.list_assignments_for_user(year, scope.current_user)
        |> Enum.find(&(&1.class_group_id == cg.id))

      _ ->
        nil
    end
  end

  # Combined mode: the context belongs to a `CombinedCourse` — one session over
  # the union of the member classes' rosters, each entry still written to the
  # student's own class.
  defp combined_course_for(scope, %TeachingContext{combined_course_id: course_id})
       when not is_nil(course_id) do
    case Curriculum.get_course(scope, course_id) do
      {:ok, course} -> course
      _ -> nil
    end
  end

  defp combined_course_for(_scope, _ctx), do: nil

  # Owning the course, or managing conduct (any class).
  defp authorized?(scope, teaching_context),
    do: owns?(scope, teaching_context) or Discipline.can_manage_conduct?(scope)

  defp owns?(_scope, nil), do: false
  defp owns?(scope, %TeachingContext{teacher_user_id: id}), do: id == scope.current_user.id

  # --- rendering ---------------------------------------------------------------

  @doc """
  The roll-call panel: title and status, the counts, one row per student with
  P / A / R buttons (`set` events), and the record button (`record` event).
  """
  attr :roll, :map, required: true
  attr :title, :string, required: true

  def roll_panel(assigns) do
    ~H"""
    <div
      id="roll-panel"
      class="ta-panel flex flex-col gap-3 !px-[18px] !py-4 shadow-[0_6px_20px_oklch(0%_0_0/0.16)]"
    >
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h2 class="font-display text-[1.3rem] font-semibold">{@title}</h2>
        <span
          id="roll-status"
          class={[
            "ta-num rounded-full px-2 py-[3px] text-[0.7rem] font-semibold",
            if(@roll.taken?, do: "bg-primary/20 text-primary", else: "bg-warning/25 text-warning")
          ]}
        >
          {if @roll.taken?, do: gettext("Appel enregistré"), else: gettext("Appel non fait")}
        </span>
      </div>

      <div class="flex flex-wrap items-center justify-between gap-2">
        <span id="roll-summary" class="ta-num text-[0.85rem]">
          {summary(@roll)}
        </span>
        <span class="text-[0.78rem] text-base-content/75">
          {gettext("Tous présents par défaut — touchez les absents et retards.")}
        </span>
      </div>

      <%= if @roll.groups do %>
        <div :for={group <- @roll.groups} id={"attendance-class-#{group.class_group.id}"}>
          <h3 class="ta-eyebrow pt-2">{group.class_group.label}</h3>
          <.roster students={group.students} roll={@roll} />
        </div>
      <% else %>
        <.roster students={@roll.students} roll={@roll} />
      <% end %>

      <button
        id="record-roll"
        type="button"
        phx-click="record"
        class="btn btn-primary mt-1 h-[46px] w-full text-[0.95rem]"
      >
        {if @roll.taken?, do: gettext("Mettre à jour l'appel"), else: gettext("Enregistrer l'appel")}
      </button>
    </div>
    """
  end

  attr :students, :list, required: true
  attr :roll, :map, required: true

  defp roster(assigns) do
    assigns = assign(assigns, :statuses, @statuses)

    ~H"""
    <ol class="flex flex-col border-t border-base-300/70">
      <li
        :for={{student, n} <- Enum.with_index(@students, 1)}
        id={"student-row-#{student.enrollment_id}"}
        class="ta-row-rule flex items-center gap-2.5 py-[5px]"
      >
        <span class="ta-num w-[22px] text-[0.72rem] text-base-content/65">{n}</span>
        <span class="flex min-w-0 flex-1 flex-col">
          <span class="truncate text-[0.92rem]">{student.student_name}</span>
          <span
            :if={(@roll.flags[student.enrollment_id] || []) != []}
            class="text-[0.72rem] text-warning"
          >
            {absent_flag(@roll.flags[student.enrollment_id])}
          </span>
        </span>
        <div
          class="flex overflow-hidden rounded-[0.4rem] border border-base-300"
          role="group"
          aria-label={student.student_name}
        >
          <button
            :for={status <- @statuses}
            type="button"
            id={"att-#{student.enrollment_id}-#{status}"}
            phx-click="set"
            phx-value-enrollment_id={student.enrollment_id}
            phx-value-status={status}
            aria-pressed={to_string(@roll.marks[student.enrollment_id] == status)}
            title={AttendanceStatus.label(status)}
            class={[
              "ta-num h-9 w-11 cursor-pointer text-[0.85rem] font-semibold transition-colors",
              status_class(status, @roll.marks[student.enrollment_id] == status)
            ]}
          >
            {short(status)}
          </button>
        </div>
      </li>
    </ol>
    """
  end

  defp summary(roll) do
    [
      ngettext("%{count} présent", "%{count} présents", count(roll, :present)),
      ngettext("%{count} absent", "%{count} absents", count(roll, :absent)),
      ngettext("%{count} retard", "%{count} retards", count(roll, :late))
    ]
    |> Enum.join(" · ")
  end

  defp absent_flag(periods) do
    labels = Enum.map_join(periods, ", ", & &1.label)

    if Enum.all?(periods, &(&1.start_time.hour < 12)),
      do: gettext("Absent en %{periods} — ce matin", periods: labels),
      else: gettext("Absent en %{periods} — aujourd'hui", periods: labels)
  end

  defp short(:present), do: "P"
  defp short(:absent), do: "A"
  defp short(:late), do: "R"

  defp status_class(:present, true), do: "bg-primary/20 text-primary"
  defp status_class(:absent, true), do: "bg-error text-primary-content"
  defp status_class(:late, true), do: "bg-warning text-primary-content"
  defp status_class(_status, false), do: "text-base-content/70 hover:bg-base-content/10"
end
