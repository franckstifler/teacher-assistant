defmodule TeacherAssistant.Academics.PedagogicalCalendar do
  @moduledoc """
  Read model for teacher pedagogical activities derived from progression entries.
  """

  require Ash.Query

  alias TeacherAssistant.Academics.ProgressionEntry
  alias TeacherAssistant.Scope

  def list_activities(%Scope{} = scope, filters \\ %{}) when is_map(filters) do
    date = Map.get(filters, :date, Date.utc_today())
    mode = Map.get(filters, :mode, :all)

    activities =
      ProgressionEntry
      |> Ash.Query.filter(progression_plan.teacher_id == ^scope.current_user.id)
      |> Ash.Query.load([
        :teaching_logs,
        :apc_lesson_plans,
        progression_plan: [
          classroom: [level_option: [:level, :option]],
          level_option_subject: [:subject]
        ]
      ])
      |> Ash.read!(scope: scope)
      |> Enum.map(&activity(&1, date))
      |> Enum.filter(&matches_mode?(&1, mode, date))
      |> Enum.sort_by(&sort_key/1)

    {:ok, activities}
  end

  defp activity(entry, date) do
    taught_hours = taught_hours(entry)
    planned_hours = entry.planned_hours || Decimal.new("0")

    %{
      entry_id: entry.id,
      plan_id: entry.progression_plan_id,
      week_number: entry.week_number,
      title: entry.title,
      planned_content: entry.planned_content,
      entry_type: entry.entry_type,
      start_date: entry.start_date,
      end_date: entry.end_date,
      planned_hours: planned_hours,
      taught_hours: taught_hours,
      status: status(entry, planned_hours, taught_hours, date),
      plan_label: plan_label(entry.progression_plan),
      class_label: class_label(entry.progression_plan),
      subject_label: subject_label(entry.progression_plan),
      has_log?: entry.teaching_logs != [],
      has_apc?: entry.apc_lesson_plans != []
    }
  end

  defp taught_hours(entry) do
    Enum.reduce(entry.teaching_logs, Decimal.new("0"), fn log, total ->
      Decimal.add(total, log.taught_hours || Decimal.new("0"))
    end)
  end

  defp status(entry, planned_hours, taught_hours, date) do
    completed_or_partial =
      cond do
        Decimal.compare(taught_hours, planned_hours) in [:eq, :gt] and
            Decimal.compare(planned_hours, Decimal.new("0")) == :gt ->
          :completed

        Decimal.compare(taught_hours, Decimal.new("0")) == :gt ->
          :partially_taught

        true ->
          nil
      end

    completed_or_partial ||
      cond do
        dated?(entry) and Date.compare(entry.end_date, date) == :lt ->
          :late

        dated?(entry) and within?(date, entry.start_date, entry.end_date) ->
          :due_today

        true ->
          :planned
      end
  end

  defp matches_mode?(_activity, :all, _date), do: true

  defp matches_mode?(activity, :today, date) do
    activity.status == :late || within?(date, activity.start_date, activity.end_date)
  end

  defp matches_mode?(activity, :week, date) do
    {start_date, end_date} = week_range(date)
    overlaps?(activity, start_date, end_date)
  end

  defp matches_mode?(activity, :month, date) do
    start_date = Date.beginning_of_month(date)
    end_date = Date.end_of_month(date)
    overlaps?(activity, start_date, end_date)
  end

  defp matches_mode?(_activity, _mode, _date), do: true

  defp overlaps?(%{start_date: nil}, _start_date, _end_date), do: false
  defp overlaps?(%{end_date: nil}, _start_date, _end_date), do: false

  defp overlaps?(activity, start_date, end_date) do
    Date.compare(activity.start_date, end_date) in [:lt, :eq] and
      Date.compare(activity.end_date, start_date) in [:gt, :eq]
  end

  defp within?(_date, nil, _end_date), do: false
  defp within?(_date, _start_date, nil), do: false

  defp within?(date, start_date, end_date) do
    Date.compare(date, start_date) in [:gt, :eq] and Date.compare(date, end_date) in [:lt, :eq]
  end

  defp dated?(%{start_date: %Date{}, end_date: %Date{}}), do: true
  defp dated?(_entry), do: false

  defp week_range(date) do
    start_date = Date.add(date, -(Date.day_of_week(date) - 1))
    {start_date, Date.add(start_date, 6)}
  end

  defp sort_key(activity) do
    {
      is_nil(activity.start_date),
      activity.start_date || ~D[9999-12-31],
      activity.week_number || 0,
      activity.title || ""
    }
  end

  defp plan_label(plan), do: "#{class_label(plan)} · #{subject_label(plan)}"

  defp class_label(%{classroom: %{level_option: %{level: level, option: option}}}) do
    "#{level.name} #{option.name}"
  end

  defp class_label(_plan), do: ""

  defp subject_label(%{level_option_subject: %{subject: subject}}), do: subject.name
  defp subject_label(_plan), do: ""
end
