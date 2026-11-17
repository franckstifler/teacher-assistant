defmodule TeacherAssistant.Academics.TeacherProfile do
  @moduledoc "Scoped teaching information for a member, viewed by school staff."

  alias TeacherAssistant.{Accounts, Attendance, Curriculum, Enrollment, Scope, Timetabling}
  alias TeacherAssistant.Academics.LessonGroups

  def allowed?(scope),
    do: Accounts.can_manage_staff?(scope) or Accounts.can_set_member_service?(scope)

  def load(%Scope{current_workspace: %{id: school_id}} = scope, member) do
    if member.workspace_id == school_id and allowed?(scope) do
      read(scope, member)
    else
      {:error, :forbidden}
    end
  rescue
    _error in [Ash.Error.Forbidden, Ash.Error.Invalid, Ash.Error.Unknown, Ash.Error.Framework] ->
      {:error, :unavailable}
  end

  def load(_scope, _member), do: {:error, :forbidden}

  defp read(%{current_academic_year: nil}, _member), do: {:error, :no_year}

  defp read(%{current_academic_year: year} = scope, member) do
    contexts = Curriculum.list_assignments_for_user(scope, year, member.user)
    timetable? = Scope.module?(scope, :emploi_du_temps)
    periods = if timetable?, do: Attendance.list_periods(scope), else: []
    days = if timetable?, do: Attendance.school_calendar(scope).lesson_days, else: []
    grid = if timetable?, do: Timetabling.teacher_timetable(scope, member.user), else: %{}

    lessons = Map.new(days, &{&1, lessons_for_day(grid, periods, &1)})

    scheduled =
      for {_day, groups} <- lessons, group <- groups, reduce: %{} do
        counts -> Map.update(counts, group.unit, 1, &(&1 + 1))
      end

    assignments =
      contexts
      |> Enum.group_by(&unit/1)
      |> Enum.map(fn {key, contexts} ->
        first = hd(contexts)
        hours = first.weekly_hours || 0
        placed = Map.get(scheduled, key, 0)

        %{
          key: key,
          subject: first.subject,
          hours: hours,
          scheduled: placed,
          missing: max(hours - placed, 0),
          classes: contexts |> Enum.map(& &1.class_group) |> Enum.sort_by(& &1.label)
        }
      end)
      |> Enum.sort_by(&{&1.subject, hd(&1.classes).label})

    form_classes =
      scope
      |> Enrollment.list_class_groups(year)
      |> Enum.filter(&(&1.form_master_user_id == member.user_id))

    {:ok,
     %{
       year: year,
       assignments: assignments,
       form_classes: form_classes,
       teaching?: :teacher in member.roles or assignments != [] or form_classes != [],
       service: Timetabling.teacher_service(scope, member.user),
       scheduled: Enum.sum(Map.values(scheduled)),
       missing: Enum.sum_by(assignments, & &1.missing),
       timetable?: timetable?,
       periods: periods,
       days: days,
       lessons: lessons,
       can_assign?: Curriculum.can_manage_assignments?(scope)
     }}
  end

  defp unit(%{combined_course_id: nil, id: id}), do: {:solo, id}
  defp unit(%{combined_course_id: id}), do: {:course, id}

  defp lessons_for_day(grid, periods, day) do
    lessons =
      for period <- periods,
          period.kind == :lesson,
          slot <- Map.get(grid, {day, period.id}, []),
          do: Map.put(slot, :period, period)

    LessonGroups.group(lessons)
  end
end
