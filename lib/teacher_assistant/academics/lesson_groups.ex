defmodule TeacherAssistant.Academics.LessonGroups do
  @moduledoc """
  A teacher's lessons as the teacher lives them (UX refonte 2026-11-03): a combined
  course placed in each member class is one lesson, not one per class; a lesson
  following the same course back to back is its « 2e heure ».

  Works on any lesson maps carrying a `:period` (with `id`, `position`,
  `start_time`, `end_time`), a `:combined_course_id` (nil for a solo course), the
  class (`:class_group_id` or a loaded `:class_group`) and `:teaching_context_id`;
  `:date` (one day when absent), `:status` and `:absent` are optional — the
  roll-call cells of `Attendance.teacher_day/4` and the slot views of
  `Timetabling.teacher_timetable/2` (with their period put in) both fit.
  """

  # The lesson's state is its most pressing member's: a roll call left to do in one
  # class keeps the whole lesson « à faire ».
  @status_order [:in_progress, :missed, :on_paper, :not_held, :upcoming, :done]

  @doc """
  The lessons grouped by date, period and course, sorted by date then period: each
  group is `%{key, date, period, unit, members, hour}` plus `status` and `absent`
  (summed) when the members carry them. `unit` is `{:course, combined_course_id}`
  or `{:solo, teaching_context_id}`; `members` are the original maps, one per class;
  `hour` counts back-to-back lessons of the same unit on the day (1, then 2…).
  """
  def group(lessons) do
    lessons
    |> Enum.group_by(&{Map.get(&1, :date), &1.period.id, unit(&1)})
    |> Enum.map(fn {{date, _period_id, unit}, members} ->
      [first | _] = members = Enum.sort_by(members, &class_label/1)

      %{
        key: key(first),
        date: date,
        period: first.period,
        unit: unit,
        members: members
      }
      |> put_status(members)
    end)
    |> Enum.sort_by(&{day_key(&1.date), &1.period.position, class_label(hd(&1.members))})
    |> number_hours()
  end

  @doc "Whether a group of `group/1` is a combined course over several classes."
  def combined?(%{unit: {:course, _}, members: [_, _ | _]}), do: true
  def combined?(_group), do: false

  @doc "The member classes' ids of a group."
  def class_ids(%{members: members}), do: Enum.map(members, &class_id/1)

  defp unit(%{combined_course_id: id}) when not is_nil(id), do: {:course, id}
  defp unit(lesson), do: {:solo, Map.get(lesson, :teaching_context_id) || class_id(lesson)}

  # The roll call of a combined lesson opens through any member class: the first.
  defp key(lesson), do: "#{class_id(lesson)}-#{lesson.period.id}"

  defp class_id(%{class_group_id: id}) when not is_nil(id), do: id
  defp class_id(%{class_group: %{id: id}}), do: id

  defp class_label(%{class_group: %{label: label}}), do: label
  defp class_label(%{class_label: label}) when is_binary(label), do: label
  defp class_label(_lesson), do: ""

  defp day_key(nil), do: 0
  defp day_key(%Date{} = date), do: Date.to_gregorian_days(date)

  defp put_status(group, [%{status: _} | _] = members) do
    statuses = MapSet.new(members, & &1.status)

    Map.merge(group, %{
      status: Enum.find(@status_order, :done, &MapSet.member?(statuses, &1)),
      absent: Enum.sum_by(members, &(Map.get(&1, :absent) || 0))
    })
  end

  defp put_status(group, _members), do: group

  # A lesson starting when the same unit's last one ended continues it.
  defp number_hours(groups) do
    {groups, _last} =
      Enum.map_reduce(groups, %{}, fn group, last ->
        hour =
          case Map.get(last, {group.date, group.unit}) do
            {end_time, hour} ->
              if Time.compare(end_time, group.period.start_time) == :eq, do: hour + 1, else: 1

            nil ->
              1
          end

        {Map.put(group, :hour, hour),
         Map.put(last, {group.date, group.unit}, {group.period.end_time, hour})}
      end)

    groups
  end
end
