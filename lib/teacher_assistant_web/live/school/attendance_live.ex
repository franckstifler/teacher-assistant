defmodule TeacherAssistantWeb.School.AttendanceLive do
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Attendance
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.TimetableSlot
  alias TeacherAssistant.Accounts.Permissions

  @valid_statuses %{"present" => :present, "absent" => :absent, "late" => :late}
  @statuses [:present, :absent, :late]

  def mount(%{"id" => id, "period_id" => period_id} = params, _session, socket) do
    scope = socket.assigns.current_scope
    date = parse_date(params["date"])

    with {:ok, cg} <- Academics.fetch_owned_class_group(id, scope.current_workspace),
         {:ok, period} <- fetch_period(period_id, scope.current_workspace),
         {:ok, slot_or_nil} <- resolve_slot(cg, date, period.id),
         true <- authorized?(scope, slot_or_nil) do
      course = combined_course_for(slot_or_nil)

      socket =
        socket
        |> assign(
          cg: cg,
          period: period,
          date: date,
          slot: slot_or_nil,
          statuses: @statuses,
          course: course
        )
        |> reload_roll()

      {:ok, socket}
    else
      false ->
        {:ok,
         socket |> put_flash(:error, gettext("Access denied.")) |> push_navigate(to: ~p"/school")}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/school/classes")}
    end
  end

  # Combined mode: the resolved slot's teaching context belongs to a
  # `CombinedCourse` — the attendance session then covers the union of every
  # member class's roster (see `load_combined_roll/1`), while recording still
  # writes each `AttendanceEntry` to the student's own class exactly as
  # before (`Attendance.record_combined_period/5`). Falls back to solo mode
  # (returns `nil`) when there's no slot, no teaching context, or the course
  # can't be resolved.
  defp combined_course_for(%TimetableSlot{
         teaching_context: %TeachingContext{combined_course_id: course_id}
       })
       when not is_nil(course_id) do
    case Academics.get_course(course_id) do
      {:ok, course} -> course
      _ -> nil
    end
  end

  defp combined_course_for(_slot_or_nil), do: nil

  defp parse_date(nil), do: Date.utc_today()

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      {:error, _} -> Date.utc_today()
    end
  end

  defp fetch_period(period_id, workspace) do
    workspace
    |> TeacherAssistant.Academics.Timetables.list_periods()
    |> Enum.find(&(&1.id == period_id))
    |> case do
      nil -> {:error, :not_found}
      period -> {:ok, period}
    end
  end

  defp resolve_slot(cg, date, period_id) do
    case Attendance.slot_for(cg, date, period_id) do
      {:ok, slot} -> {:ok, slot}
      {:error, :no_slot} -> {:ok, nil}
    end
  end

  defp authorized?(scope, slot) do
    owns_slot?(scope, slot) or Permissions.conduct_manager?(scope)
  end

  defp owns_slot?(_scope, nil), do: false

  defp owns_slot?(scope, slot),
    do: slot.teaching_context.teacher_user_id == scope.current_user.id

  # Roll starts with every student PRESENT (the cahier d'appel default); the
  # teacher only taps the absent/late few. `taken?` records whether the roll has
  # already been saved, so "all present" is distinguishable from "not yet done".
  defp load_roll(socket) do
    %{students: roster} =
      Attendance.period_roll(socket.assigns.cg, socket.assigns.period, socket.assigns.date)

    taken? = Enum.any?(roster, &(&1.status != nil))
    roll = Map.new(roster, fn s -> {s.enrollment_id, s.status || :present} end)

    students =
      Enum.map(roster, &%{enrollment_id: &1.enrollment_id, student_name: &1.student_name})

    assign(socket, students: students, roll: roll, taken?: taken?)
  end

  # Combined mode: same roll shape as `load_roll/1` (a flat `students` list
  # plus an `enrollment_id => status` `roll` map, so `set`/`record` work
  # unchanged), but sourced from `combined_period_roll/3` and keeping the
  # per-class `groups` around for the grouped render.
  defp load_combined_roll(socket) do
    groups =
      Attendance.combined_period_roll(
        socket.assigns.course,
        socket.assigns.period,
        socket.assigns.date
      )

    all_students = Enum.flat_map(groups, & &1.students)
    taken? = Enum.any?(all_students, &(&1.status != nil))
    roll = Map.new(all_students, fn s -> {s.enrollment_id, s.status || :present} end)

    students =
      Enum.map(all_students, &%{enrollment_id: &1.enrollment_id, student_name: &1.student_name})

    assign(socket, groups: groups, students: students, roll: roll, taken?: taken?)
  end

  defp reload_roll(%{assigns: %{course: %CombinedCourse{}}} = socket),
    do: load_combined_roll(socket)

  defp reload_roll(socket), do: load_roll(socket)

  def handle_event("set", %{"enrollment_id" => enrollment_id, "status" => status_str}, socket) do
    with %{} <- Enum.find(socket.assigns.students, &(&1.enrollment_id == enrollment_id)),
         status when not is_nil(status) <- Map.get(@valid_statuses, status_str) do
      {:noreply, assign(socket, :roll, Map.put(socket.assigns.roll, enrollment_id, status))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("record", _params, socket) do
    scope = socket.assigns.current_scope

    cond do
      not Permissions.operating_allowed?(scope) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("École en attente de vérification — enregistrement indisponible.")
         )}

      authorized?(scope, socket.assigns.slot) ->
        marks =
          Enum.map(socket.assigns.students, fn s ->
            {s.enrollment_id, Map.fetch!(socket.assigns.roll, s.enrollment_id)}
          end)

        case record_marks(socket, marks, scope.current_user.id) do
          {:ok, _count} ->
            {:noreply, socket |> put_flash(:info, gettext("Appel enregistré")) |> reload_roll()}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Impossible d'enregistrer l'appel"))}
        end

      true ->
        {:noreply, socket}
    end
  end

  defp record_marks(%{assigns: %{course: %CombinedCourse{} = course}} = socket, marks, user_id) do
    Attendance.record_combined_period(
      course,
      socket.assigns.period,
      socket.assigns.date,
      marks,
      user_id
    )
  end

  defp record_marks(socket, marks, user_id) do
    teaching_context = socket.assigns.slot && socket.assigns.slot.teaching_context

    Attendance.record_period(
      socket.assigns.cg,
      socket.assigns.period,
      teaching_context,
      socket.assigns.date,
      marks,
      user_id
    )
  end

  defp status_label(:present), do: gettext("Présent")
  defp status_label(:absent), do: gettext("Absent")
  defp status_label(:late), do: gettext("Retard")

  defp status_short(:present), do: "P"
  defp status_short(:absent), do: "A"
  defp status_short(:late), do: "R"

  defp active_class(:present), do: "btn-success"
  defp active_class(:absent), do: "btn-error"
  defp active_class(:late), do: "btn-warning"

  defp count(roll, status), do: Enum.count(roll, fn {_id, s} -> s == status end)

  # Combined mode: one session over the union of every member class's roll,
  # grouped under a class heading (mirrors `Teacher.MarksLive`'s combined
  # render) — the teacher records once, and each `AttendanceEntry` still
  # lands on the student's own class via `record_combined_period/5`.
  def render(%{course: %CombinedCourse{}} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="class-attendance" class="mx-auto max-w-2xl space-y-4">
        <.page_header
          eyebrow={gettext("École")}
          title={"#{@course.label} — #{gettext("Appel")} — #{@period.label}"}
        />

        <div class="flex flex-wrap items-center justify-between gap-2 text-sm">
          <p class="text-base-content/70">{Date.to_string(@date)}</p>
          <p id="roll-status" class={["badge", (@taken? && "badge-success") || "badge-ghost"]}>
            {if @taken?, do: gettext("Appel enregistré"), else: gettext("Appel non fait")}
          </p>
        </div>

        <p id="roll-summary" class="ta-num text-sm text-base-content/70">
          {gettext("%{p} présents · %{a} absents · %{r} retards",
            p: count(@roll, :present),
            a: count(@roll, :absent),
            r: count(@roll, :late)
          )}
        </p>

        <div :for={group <- @groups} id={"attendance-class-#{group.class_group.id}"} class="space-y-1">
          <h3 class="ta-eyebrow">{group.class_group.label}</h3>
          <.roster_list students={group.students} roll={@roll} statuses={@statuses} />
        </div>

        <.button id="record-roll" phx-click="record" class="btn btn-primary w-full">
          {if @taken?, do: gettext("Mettre à jour l'appel"), else: gettext("Enregistrer l'appel")}
        </.button>
      </section>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="class-attendance" class="mx-auto max-w-2xl space-y-4">
        <.page_header
          eyebrow={gettext("École")}
          title={"#{@cg.label} — #{gettext("Appel")} — #{@period.label}"}
        />

        <div class="flex flex-wrap items-center justify-between gap-2 text-sm">
          <p class="text-base-content/70">{Date.to_string(@date)}</p>
          <p id="roll-status" class={["badge", (@taken? && "badge-success") || "badge-ghost"]}>
            {if @taken?, do: gettext("Appel enregistré"), else: gettext("Appel non fait")}
          </p>
        </div>

        <p id="roll-summary" class="ta-num text-sm text-base-content/70">
          {gettext("%{p} présents · %{a} absents · %{r} retards",
            p: count(@roll, :present),
            a: count(@roll, :absent),
            r: count(@roll, :late)
          )}
        </p>

        <.roster_list students={@students} roll={@roll} statuses={@statuses} />

        <.button id="record-roll" phx-click="record" class="btn btn-primary w-full">
          {if @taken?, do: gettext("Mettre à jour l'appel"), else: gettext("Enregistrer l'appel")}
        </.button>
      </section>
    </Layouts.app>
    """
  end

  attr :students, :list, required: true
  attr :roll, :map, required: true
  attr :statuses, :list, required: true

  defp roster_list(assigns) do
    ~H"""
    <ul class="space-y-1">
      <li
        :for={student <- @students}
        id={"student-row-#{student.enrollment_id}"}
        class="ta-leaf flex items-center justify-between gap-3"
      >
        <span class="min-w-0 flex-1 truncate">{student.student_name}</span>
        <div class="join" role="group" aria-label={student.student_name}>
          <button
            :for={status <- @statuses}
            type="button"
            id={"att-#{student.enrollment_id}-#{status}"}
            phx-click="set"
            phx-value-enrollment_id={student.enrollment_id}
            phx-value-status={status}
            aria-pressed={to_string(Map.get(@roll, student.enrollment_id) == status)}
            title={status_label(status)}
            class={[
              "join-item btn btn-sm",
              (Map.get(@roll, student.enrollment_id) == status && active_class(status)) ||
                "btn-ghost"
            ]}
          >
            {status_short(status)}
          </button>
        </div>
      </li>
    </ul>
    """
  end
end
