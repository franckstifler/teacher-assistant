defmodule TeacherAssistant.Academics.PaperWeek do
  @moduledoc """
  Paper roll call (spec 2026-10-28 §2–3): one class's week as the printed sheet and the
  entry screen show it, and the save of a typed-in sheet.

  A lesson's `state` is `:app` (taken in the app), `:paper` (typed in from a sheet),
  `:not_held` (« cours non assuré ») or `:empty`. Saving never touches an `:app`
  lesson, a closed day or a lesson outside the week; a ticked column records every
  student of the roster — « A » absent, « R » late, sent home for fees `:sent_home`
  whatever was typed, everyone else present.
  """

  require Ash.Query

  alias TeacherAssistant.{Attendance, Discipline, Enrollment, FeeControl, Scope}

  alias TeacherAssistant.Academics.{
    ClassGroup,
    DayOfWeek,
    LessonNotHeld,
    PaperRollCall,
    Reference,
    SchoolCalendar
  }

  def read(%Scope{} = scope, %ClassGroup{} = cg, %Date{} = date) do
    {monday, saturday} = PaperRollCall.week(date)

    roster = Enrollment.list_roster(scope, cg)
    enrollment_ids = Enum.map(roster, & &1.enrollment.id)

    entries =
      cg.id
      |> Attendance.for_class_range!(monday, saturday, scope: scope)
      |> Enum.group_by(&{&1.date, &1.period_id})

    lessons =
      scope
      |> Attendance.class_lessons(cg, monday, saturday, Reference.now())
      |> Enum.group_by(& &1.date)

    days =
      for date <- Date.range(monday, saturday),
          day = day(scope, date, Map.get(lessons, date, []), entries, enrollment_ids),
          do: day

    %{
      monday: monday,
      saturday: saturday,
      students:
        roster
        |> Enum.with_index(1)
        |> Enum.map(fn {r, n} ->
          %{enrollment_id: r.enrollment.id, number: n, student_name: r.student.full_name}
        end),
      days: days
    }
  end

  # A school day: its open lessons, or `closed` with the holiday's name; nil when the
  # school, or this class, has no lessons that day.
  defp day(scope, date, cells, entries, enrollment_ids) do
    case Attendance.day_off(scope, date) do
      :no_lessons ->
        nil

      nil when cells == [] ->
        nil

      {:holiday, label} ->
        %{date: date, label: label(date), closed: label, lessons: []}

      nil ->
        sent_home = FeeControl.sent_home_ids(scope, enrollment_ids, date)

        %{
          date: date,
          label: label(date),
          closed: nil,
          lessons:
            Enum.map(cells, &lesson(&1, Map.get(entries, {date, &1.period.id}, []), sent_home))
        }
    end
  end

  defp label(date), do: "#{DayOfWeek.label(SchoolCalendar.weekday(date))} #{date.day}"

  defp lesson(cell, entries, sent_home) do
    %{
      date: cell.date,
      period: cell.period,
      teaching_context_id: cell.teaching_context_id,
      code: cell.code,
      subject: cell.subject,
      state: state(cell, entries),
      # Not taken place yet: nothing to type in or close.
      upcoming?: cell.status == :upcoming,
      marks: Map.new(entries, &{&1.enrollment_id, &1.status}),
      sent_home: sent_home
    }
  end

  defp state(_cell, [_ | _] = entries),
    do: if(Enum.any?(entries, &(&1.source == :app)), do: :app, else: :paper)

  defp state(%{status: :not_held}, []), do: :not_held
  defp state(_cell, []), do: :empty

  @doc false
  def save(%Scope{} = scope, %ClassGroup{} = cg, %Date{} = date, columns) when is_list(columns) do
    cond do
      not Scope.school_verified?(scope) ->
        {:error, :unverified}

      not Discipline.can_manage_conduct?(scope) ->
        {:error, :forbidden}

      true ->
        week = read(scope, cg, date)

        index =
          for day <- week.days, lesson <- day.lessons, into: %{} do
            {{lesson.date, lesson.period.id}, lesson}
          end

        students = Enum.map(week.students, & &1.enrollment_id)

        TeacherAssistant.Repo.transaction(fn ->
          Enum.reduce(columns, %{saved: 0, not_held: 0, unmarked: 0}, fn column, acc ->
            lesson = Map.get(index, {column.date, column.period_id})

            case apply_column(scope, cg, lesson, column, students) do
              :skipped -> acc
              {:ok, key} -> Map.update!(acc, key, &(&1 + 1))
              {:error, error} -> TeacherAssistant.Repo.rollback(error)
            end
          end)
        end)
    end
  end

  defp apply_column(_scope, _cg, nil, _column, _students), do: :skipped
  defp apply_column(_scope, _cg, %{state: :app}, _column, _students), do: :skipped
  defp apply_column(_scope, _cg, %{upcoming?: true}, _column, _students), do: :skipped

  # « Non assuré » un-marked: the lesson is back to be typed in (spec §3).
  defp apply_column(scope, cg, %{state: :not_held} = lesson, %{mode: :skip}, _students) do
    with :ok <- unmark_not_held(scope, cg, lesson), do: {:ok, :unmarked}
  end

  defp apply_column(_scope, _cg, _lesson, %{mode: :skip}, _students), do: :skipped

  defp apply_column(scope, cg, lesson, %{mode: :taken, marks: typed}, students) do
    marks =
      for id <- students do
        cond do
          MapSet.member?(lesson.sent_home, id) -> {id, :sent_home}
          Map.get(typed, id) in [:absent, :late] -> {id, Map.fetch!(typed, id)}
          true -> {id, :present}
        end
      end

    with :ok <- unmark_not_held(scope, cg, lesson),
         {:ok, _} <-
           Attendance.record_period(
             scope,
             cg,
             lesson.period,
             lesson.teaching_context_id,
             lesson.date,
             marks,
             source: :paper
           ) do
      {:ok, :saved}
    end
  end

  defp apply_column(_scope, _cg, %{state: :not_held}, %{mode: :not_held}, _students),
    do: :skipped

  # A sheet typed in earlier and now « non assuré »: its paper entries go.
  defp apply_column(scope, cg, lesson, %{mode: :not_held}, _students) do
    with :ok <- remove_paper_entries(scope, cg, lesson),
         {:ok, _} <-
           LessonNotHeld
           |> Ash.Changeset.for_create(
             :mark,
             %{class_group_id: cg.id, period_id: lesson.period.id, date: lesson.date},
             scope: scope
           )
           |> Ash.create() do
      {:ok, :not_held}
    end
  end

  defp unmark_not_held(_scope, _cg, %{state: state}) when state != :not_held, do: :ok

  defp unmark_not_held(scope, cg, lesson) do
    LessonNotHeld
    |> Ash.Query.for_read(
      :for_classes_range,
      %{class_group_ids: [cg.id], first: lesson.date, last: lesson.date},
      scope: scope
    )
    |> Ash.Query.filter(period_id == ^lesson.period.id)
    |> Ash.read!()
    |> destroy_all(scope)
  end

  defp remove_paper_entries(_scope, _cg, %{state: state}) when state != :paper, do: :ok

  defp remove_paper_entries(scope, cg, lesson) do
    cg.id
    |> Attendance.for_class_range!(lesson.date, lesson.date, scope: scope)
    |> Enum.filter(&(&1.period_id == lesson.period.id))
    |> destroy_all(scope)
  end

  defp destroy_all(records, scope) do
    Enum.reduce_while(records, :ok, fn record, :ok ->
      case Ash.destroy(record, scope: scope) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
