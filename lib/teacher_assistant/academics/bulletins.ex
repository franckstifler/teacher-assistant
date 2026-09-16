defmodule TeacherAssistant.Academics.Bulletins do
  @moduledoc """
  Pure, deterministic cross-subject bulletin computation (Francophone /20).
  No database access — operates on plain maps, like `Academics.Marks`. Reuses
  `Marks.subject_average/2` for the per-subject figure so the two never drift.
  """
  alias TeacherAssistant.Academics.Marks

  @pass Decimal.new(10)
  @felicitations Decimal.new(16)
  @encouragements Decimal.new(14)
  @tableau Decimal.new(12)

  def compile(students, subjects) do
    inputs =
      Enum.map(subjects, fn subj ->
        per_student_avg =
          Map.new(students, fn s ->
            student_marks = Enum.filter(subj.marks, &(&1.student_id == s.id))
            {s.id, Marks.subject_average(student_marks, subj.assessments_by_id)}
          end)

        %{
          context_id: subj.context_id,
          label: subj.label,
          coefficient: subj.coefficient,
          per_student_avg: per_student_avg,
          components: nil
        }
      end)

    aggregate(students, inputs)
  end

  @doc """
  Ranking/stats/distinctions over pre-computed per-subject averages. Shared by the
  séquentiel path (`compile/2`) and the periodic path (trimester/annual), so the
  arithmetic never drifts. `subject_inputs` carry `per_student_avg` (%{id => Decimal | nil})
  and optional per-student `components` for the bulletin breakdown.
  """
  def aggregate(students, subject_inputs) do
    subject_views =
      Enum.map(subject_inputs, fn subj ->
        graded = subj.per_student_avg |> Map.values() |> Enum.reject(&is_nil/1)

        %{
          context_id: subj.context_id,
          label: subj.label,
          coefficient: subj.coefficient,
          per_student_avg: subj.per_student_avg,
          components: subj.components,
          class_min: min_of(graded),
          class_max: max_of(graded),
          ranks: rank_map(subj.per_student_avg)
        }
      end)

    per_student_core =
      Map.new(students, fn s ->
        rows =
          Enum.map(subject_views, fn sv ->
            avg = sv.per_student_avg[s.id]

            %{
              context_id: sv.context_id,
              label: sv.label,
              coefficient: sv.coefficient,
              average: avg,
              note_x_coef: avg && Decimal.mult(avg, sv.coefficient),
              subject_rank: sv.ranks[s.id],
              class_min: sv.class_min,
              class_max: sv.class_max,
              components: sv.components && sv.components[s.id]
            }
          end)

        graded_rows = Enum.filter(rows, &(&1.average != nil))
        total_coef = sum(Enum.map(graded_rows, & &1.coefficient))
        total_points = sum(Enum.map(graded_rows, & &1.note_x_coef))

        moy =
          if Decimal.equal?(total_coef, Decimal.new(0)),
            do: nil,
            else: Decimal.div(total_points, total_coef)

        {s.id,
         %{
           subjects: rows,
           total_points: if(graded_rows == [], do: nil, else: total_points),
           total_coef: total_coef,
           moyenne_generale: moy,
           mention: Marks.mention(moy),
           rank: nil
         }}
      end)

    moy_map = Map.new(per_student_core, fn {id, d} -> {id, d.moyenne_generale} end)
    class_ranks = rank_map(moy_map)
    per_student = Map.new(per_student_core, fn {id, d} -> {id, %{d | rank: class_ranks[id]}} end)

    graded =
      per_student |> Map.values() |> Enum.map(& &1.moyenne_generale) |> Enum.reject(&is_nil/1)

    %{
      per_student: per_student,
      effectif: length(students),
      graded_count: length(graded),
      class_average: mean(graded),
      pass_rate: pass_rate(graded),
      highest: max_of(graded),
      lowest: min_of(graded),
      by_sex: %{m: sex_stats(students, per_student, :m), f: sex_stats(students, per_student, :f)},
      distinctions: distinctions(students, per_student)
    }
  end

  # --- ex-aequo ranking over a %{id => Decimal | nil} map ---
  defp rank_map(avg_map) do
    ordered =
      avg_map
      |> Enum.reject(fn {_id, a} -> is_nil(a) end)
      |> Enum.sort_by(fn {_id, a} -> a end, &(Decimal.compare(&1, &2) != :lt))

    {ranks, _} =
      Enum.reduce(ordered, {%{}, nil}, fn {id, a}, {acc, prev} ->
        position = map_size(acc) + 1

        rank =
          case prev do
            {pa, pr} -> if Decimal.equal?(pa, a), do: pr, else: position
            nil -> position
          end

        {Map.put(acc, id, rank), {a, rank}}
      end)

    ranks
  end

  defp distinctions(students, per_student) do
    base = %{felicitations: [], encouragements: [], tableau_honneur: []}

    Enum.reduce(students, base, fn s, acc ->
      d = per_student[s.id]
      all_pass? = Enum.all?(d.subjects, fn r -> is_nil(r.average) or gte(r.average, @pass) end)

      cond do
        is_nil(d.moyenne_generale) or not all_pass? -> acc
        gte(d.moyenne_generale, @felicitations) -> prepend(acc, :felicitations, s.id)
        gte(d.moyenne_generale, @encouragements) -> prepend(acc, :encouragements, s.id)
        gte(d.moyenne_generale, @tableau) -> prepend(acc, :tableau_honneur, s.id)
        true -> acc
      end
    end)
  end

  defp prepend(acc, key, id), do: Map.update!(acc, key, &(&1 ++ [id]))

  defp sex_stats(students, per_student, sex) do
    graded =
      students
      |> Enum.filter(&(&1.sex == sex))
      |> Enum.map(&per_student[&1.id].moyenne_generale)
      |> Enum.reject(&is_nil/1)

    %{class_average: mean(graded), pass_rate: pass_rate(graded), graded_count: length(graded)}
  end

  defp gte(a, b), do: Decimal.compare(a, b) != :lt
  defp sum(list), do: Enum.reduce(list, Decimal.new(0), &Decimal.add(&1, &2))
  defp mean([]), do: nil
  defp mean(list), do: Decimal.div(sum(list), Decimal.new(length(list)))
  defp pass_rate([]), do: 0.0
  defp pass_rate(l), do: Enum.count(l, &gte(&1, @pass)) / length(l)
  defp max_of([]), do: nil
  defp max_of(l), do: Enum.reduce(l, &if(Decimal.compare(&1, &2) == :gt, do: &1, else: &2))
  defp min_of([]), do: nil
  defp min_of(l), do: Enum.reduce(l, &if(Decimal.compare(&1, &2) == :lt, do: &1, else: &2))
end
