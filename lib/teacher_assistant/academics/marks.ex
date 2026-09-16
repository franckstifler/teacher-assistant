defmodule TeacherAssistant.Academics.Marks do
  @moduledoc """
  Pure, deterministic per-subject mark statistics (Francophone /20).
  No database access — operates on plain maps, like `Academics.Coverage`.
  """

  @pass Decimal.new(10)
  @scale Decimal.new(20)

  @doc "Mention label for a /20 average, per domain doc bands (10/12/14/16/18)."
  def mention(nil), do: nil

  def mention(%Decimal{} = avg) do
    cond do
      Decimal.compare(avg, Decimal.new(18)) != :lt -> :excellent
      Decimal.compare(avg, Decimal.new(16)) != :lt -> :tres_bien
      Decimal.compare(avg, Decimal.new(14)) != :lt -> :bien
      Decimal.compare(avg, Decimal.new(12)) != :lt -> :assez_bien
      Decimal.compare(avg, @pass) != :lt -> :passable
      true -> nil
    end
  end

  @doc "Unweighted mean of the non-nil séquence averages (Cameroon annual rule)."
  def annual_average(sequence_averages) do
    graded = Enum.reject(sequence_averages, &is_nil/1)
    mean(graded)
  end

  @doc "Full per-séquence subject summary. See module docs / plan for the shape."
  def summarize(students, assessments, marks) do
    weights = Map.new(assessments, fn a -> {a.id, a} end)

    marks_by_student =
      marks
      |> Enum.group_by(& &1.student_id)

    per_student =
      Map.new(students, fn s ->
        avg = subject_average(Map.get(marks_by_student, s.id, []), weights)
        {s.id, %{average: avg, mention: mention(avg), rank: nil}}
      end)

    per_student = assign_ranks(per_student)

    graded = graded_averages(students, per_student)

    %{
      per_student: per_student,
      class_average: mean(graded),
      pass_rate: pass_rate(graded),
      highest: max_of(graded),
      lowest: min_of(graded),
      graded_count: length(graded),
      by_sex: %{
        m: sex_stats(students, per_student, :m),
        f: sex_stats(students, per_student, :f)
      }
    }
  end

  # --- per-student weighted average, normalized to /20 over non-nil marks ---

  @doc """
  Weighted /20 average for one student in one subject/séquence.

  `marks` = `[%{assessment_id, score}]` (score may be nil); `weights` =
  `%{assessment_id => %{weight, max_score}}`. Returns a `%Decimal{}` on the /20
  scale, or nil when nothing is graded. Shared with `Academics.Bulletins` so the
  per-subject figure is computed identically in both places.
  """
  def subject_average(marks, weights) do
    contributions =
      marks
      |> Enum.reject(&is_nil(&1.score))
      |> Enum.map(fn m ->
        a = Map.fetch!(weights, m.assessment_id)
        normalized = Decimal.div(Decimal.mult(m.score, @scale), a.max_score)
        {Decimal.mult(normalized, a.weight), a.weight}
      end)

    case contributions do
      [] ->
        nil

      list ->
        total = Enum.reduce(list, Decimal.new(0), fn {c, _w}, acc -> Decimal.add(acc, c) end)
        weight = Enum.reduce(list, Decimal.new(0), fn {_c, w}, acc -> Decimal.add(acc, w) end)
        # Defensive only: assessments always carry positive weight, so this
        # guards against a degenerate all-zero-weight assessment set.
        if Decimal.equal?(weight, Decimal.new(0)), do: nil, else: Decimal.div(total, weight)
    end
  end

  # --- ranking: sort graded desc, ties share a rank (ex-aequo) ---

  defp assign_ranks(per_student) do
    ranked =
      per_student
      |> Enum.filter(fn {_id, %{average: a}} -> not is_nil(a) end)
      |> Enum.sort_by(fn {_id, %{average: a}} -> a end, &(Decimal.compare(&1, &2) != :lt))

    {ranks, _} =
      Enum.reduce(ranked, {%{}, nil}, fn {id, %{average: a}}, {acc, prev} ->
        position = map_size(acc) + 1

        rank =
          case prev do
            {prev_avg, prev_rank} ->
              if Decimal.equal?(prev_avg, a), do: prev_rank, else: position

            nil ->
              position
          end

        {Map.put(acc, id, rank), {a, rank}}
      end)

    Map.new(per_student, fn {id, data} ->
      {id, %{data | rank: Map.get(ranks, id)}}
    end)
  end

  # --- aggregates ---

  defp graded_averages(students, per_student) do
    students
    |> Enum.map(fn s -> per_student[s.id].average end)
    |> Enum.reject(&is_nil/1)
  end

  defp sex_stats(students, per_student, sex) do
    graded =
      students
      |> Enum.filter(fn s -> s.sex == sex end)
      |> Enum.map(fn s -> per_student[s.id].average end)
      |> Enum.reject(&is_nil/1)

    %{class_average: mean(graded), pass_rate: pass_rate(graded), graded_count: length(graded)}
  end

  defp pass_rate([]), do: 0.0

  defp pass_rate(averages) do
    passed = Enum.count(averages, fn a -> Decimal.compare(a, @pass) != :lt end)
    passed / length(averages)
  end

  defp mean([]), do: nil

  defp mean(list) do
    sum = Enum.reduce(list, Decimal.new(0), &Decimal.add(&1, &2))
    Decimal.div(sum, Decimal.new(length(list)))
  end

  defp max_of([]), do: nil

  defp max_of(list),
    do: Enum.reduce(list, fn a, acc -> if Decimal.compare(a, acc) == :gt, do: a, else: acc end)

  defp min_of([]), do: nil

  defp min_of(list),
    do: Enum.reduce(list, fn a, acc -> if Decimal.compare(a, acc) == :lt, do: a, else: acc end)
end
