defmodule TeacherAssistant.Academics.MissingMarksReport do
  @moduledoc "Student-level detail for the school's séquence entry tracking."

  require Ash.Query

  alias TeacherAssistant.Academics.{EntryProgress, Student}

  def load(scope, year, sequence, grid) do
    courses =
      for row <- grid.rows, subject <- grid.subjects, cell = row.cells[subject.key], cell do
        %{
          class: row.class_group,
          subject: subject.label,
          teacher: cell.teacher,
          context: cell.teaching_context
        }
      end

    pending =
      EntryProgress.missing_entries(scope, year, sequence, Enum.map(courses, & &1.context))

    {totals, missing, unassessed} =
      Enum.reduce(courses, {%{}, %{}, []}, fn course, {totals, missing, unassessed} ->
        %{students: students, assessments: assessments} = Map.fetch!(pending, course.context.id)

        case assessments do
          [] ->
            {totals, missing,
             if(MapSet.size(students) > 0, do: [course | unassessed], else: unassessed)}

          assessments ->
            totals =
              Enum.reduce(students, totals, fn student_id, acc ->
                Map.update(
                  acc,
                  {course.class.id, student_id},
                  length(assessments),
                  &(&1 + length(assessments))
                )
              end)

            missing =
              Enum.reduce(assessments, missing, fn entry, acc ->
                info = %{
                  subject: course.subject,
                  teacher: course.teacher,
                  label: entry.assessment.label
                }

                Enum.reduce(entry.missing, acc, fn student_id, acc ->
                  Map.update(acc, {course.class.id, student_id}, [info], &[info | &1])
                end)
              end)

            {totals, missing, unassessed}
        end
      end)

    names = load_names(scope, missing |> Map.keys() |> Enum.map(&elem(&1, 1)) |> Enum.uniq())
    classes = Map.new(grid.rows, &{&1.class_group.id, &1.class_group})

    students =
      missing
      |> Enum.flat_map(fn {{class_id, student_id} = key, pending} ->
        with {:ok, name} <- Map.fetch(names, student_id) do
          [
            %{
              id: student_id,
              class: Map.fetch!(classes, class_id),
              name: name,
              missing: Enum.reverse(pending),
              total: Map.fetch!(totals, key),
              zero?: length(pending) == Map.fetch!(totals, key)
            }
          ]
        else
          :error -> []
        end
      end)
      |> Enum.sort_by(&{&1.class.label, String.downcase(&1.name), &1.id})

    %{
      classes: Enum.map(grid.rows, & &1.class_group),
      students: students,
      unassessed: Enum.reverse(unassessed)
    }
  end

  defp load_names(_scope, []), do: %{}

  defp load_names(scope, ids) do
    Student
    |> Ash.Query.filter(id in ^ids)
    |> Ash.Query.select([:full_name])
    |> Ash.read!(scope: scope)
    |> Map.new(&{&1.id, &1.full_name})
  end
end
