defmodule TeacherAssistant.Academics.TeacherProfile do
  @moduledoc "Scoped teaching information for a member, viewed by school staff."

  alias TeacherAssistant.{Accounts, Attendance, Curriculum, Enrollment, Scope, Timetabling}
  alias TeacherAssistant.Academics.{LessonGroups, SchoolCalendar}

  def allowed?(scope),
    do: Accounts.can_manage_staff?(scope) or Accounts.can_set_member_service?(scope)

  @doc """
  The member's teaching profile for the scope's academic year, or `{:error, reason}`:
  `:forbidden` (another school's member, or a viewer who may neither manage staff
  nor set services), `:no_year` or `:unavailable` (a read failed).

  Pass `allowed?: true | false` when the caller already knows `allowed?/1`.
  """
  def load(scope, member, opts \\ [])

  def load(%Scope{current_workspace: %{id: school_id}} = scope, member, opts) do
    allowed? = Keyword.get_lazy(opts, :allowed?, fn -> allowed?(scope) end)

    if member.workspace_id == school_id and allowed? do
      read(scope, member)
    else
      {:error, :forbidden}
    end
  rescue
    _error in [Ash.Error.Forbidden, Ash.Error.Invalid, Ash.Error.Unknown, Ash.Error.Framework] ->
      {:error, :unavailable}
  end

  def load(_scope, _member, _opts), do: {:error, :forbidden}

  defp read(%{current_academic_year: nil}, _member), do: {:error, :no_year}

  defp read(%{current_academic_year: year} = scope, member) do
    case Accounts.fetch_school_profile(scope) do
      {:ok, school} -> {:ok, build(scope, year, school, member)}
      _error -> {:error, :unavailable}
    end
  end

  defp build(scope, year, school, member) do
    contexts = Curriculum.list_assignments_for_user(scope, year, member.user)
    timetable? = Scope.module?(scope, :emploi_du_temps)
    periods = if timetable?, do: Attendance.list_periods(scope), else: []
    grid = if timetable?, do: Timetabling.teacher_timetable(scope, member.user), else: %{}

    # The school's lesson days, as `Attendance.school_calendar/1` has them (its
    # holidays are not needed here).
    days =
      if timetable?,
        do:
          SchoolCalendar.new(school.lesson_days, school.wednesday_afternoon_off?, []).lesson_days,
        else: []

    lessons = LessonGroups.by_day(grid, periods, days)

    scheduled =
      for {_day, groups} <- lessons, group <- groups, reduce: %{} do
        counts -> Map.update(counts, group.unit, 1, &(&1 + 1))
      end

    assignments = assignments(contexts, scheduled)

    form_classes =
      scope
      |> Enrollment.list_class_groups(year)
      |> Enum.filter(&(&1.form_master_user_id == member.user_id))

    %{
      year: year,
      assignments: assignments,
      subjects: subjects(assignments),
      form_classes: form_classes,
      teaching?: :teacher in member.roles or assignments != [] or form_classes != [],
      service:
        Timetabling.service_from(
          contexts,
          member.user_id,
          member.statutory_hours,
          school.statutory_hours
        ),
      scheduled: Enum.sum(Map.values(scheduled)),
      missing: Enum.sum_by(assignments, & &1.missing),
      timetable?: timetable?,
      periods: periods,
      days: days,
      lessons: lessons,
      cells: cells(grid, lessons),
      can_assign?: Curriculum.can_manage_assignments?(scope)
    }
  end

  # One entry per course (a combined course once, with its classes), with its
  # weekly hours against the lessons placed: `placement` is `:over`, `:under` or `:ok`.
  defp assignments(contexts, scheduled) do
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
        placement: placement(placed, hours),
        classes: contexts |> Enum.map(& &1.class_group) |> Enum.sort_by(& &1.label)
      }
    end)
    |> Enum.sort_by(&{&1.subject, hd(&1.classes).label})
  end

  defp placement(placed, hours) when placed > hours, do: :over
  defp placement(placed, hours) when placed < hours, do: :under
  defp placement(_placed, _hours), do: :ok

  # The courses by subject, each subject with its total weekly hours.
  defp subjects(assignments) do
    assignments
    |> Enum.chunk_by(& &1.subject)
    |> Enum.map(fn [first | _] = courses ->
      %{subject: first.subject, hours: Enum.sum_by(courses, & &1.hours), courses: courses}
    end)
  end

  # The week grid's cells, `{day, period_id} => %{lessons, clash?}`, for occupied
  # lesson cells only.
  defp cells(grid, lessons) do
    for {day, groups} <- lessons,
        {period_id, cell_lessons} <- Enum.group_by(groups, & &1.period.id),
        into: %{} do
      {{day, period_id},
       %{
         lessons: cell_lessons,
         clash?: LessonGroups.clash?(Map.get(grid, {day, period_id}, []))
       }}
    end
  end

  defp unit(%{combined_course_id: nil, id: id}), do: {:solo, id}
  defp unit(%{combined_course_id: id}), do: {:course, id}
end
