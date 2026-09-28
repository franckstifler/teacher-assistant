defmodule TeacherAssistant.Academics.Marks do
  @moduledoc """
  Pure, deterministic per-subject mark statistics (Francophone /20).
  No database access — operates on plain maps, like `Academics.Coverage`.
  """

  alias TeacherAssistant.Academics.GradingRules

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

  @doc "Full per-séquence subject summary, under the school's `GradingRules`."
  def summarize(students, assessments, marks, rules \\ %GradingRules{}) do
    weights = Map.new(assessments, fn a -> {a.id, a} end)
    marks_by_student = Enum.group_by(marks, & &1.student_id)

    precise =
      Map.new(students, fn s ->
        {s.id, subject_average(Map.get(marks_by_student, s.id, []), weights, rules)}
      end)

    ranks =
      students
      |> Enum.map(fn s ->
        %{
          id: s.id,
          average: GradingRules.round_average(precise[s.id], rules),
          precise: precise[s.id],
          name: Map.get(s, :name, "")
        }
      end)
      |> GradingRules.ranks(rules)

    per_student =
      Map.new(students, fn s ->
        avg = GradingRules.round_average(precise[s.id], rules)
        {s.id, %{average: avg, mention: mention(avg), rank: ranks[s.id]}}
      end)

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
  Weighted /20 average for one student in one subject/séquence, under the school's
  absence rule. `marks` = `[%{assessment_id, score, status}]` (`status` optional:
  graded when a score is present); `weights` = `%{assessment_id => %{weight, max_score}}`.
  Graded marks count; an `:absent` mark counts as 0 under `absence: :zero` and is left
  out otherwise; an `:excused` mark is always left out. Returns nil when nothing counts.
  """
  def subject_average(marks, weights, rules \\ %GradingRules{}) do
    contributions =
      marks
      |> Enum.flat_map(&counted_score(&1, rules))
      |> Enum.map(fn {assessment_id, score} ->
        a = Map.fetch!(weights, assessment_id)
        normalized = Decimal.div(Decimal.mult(score, @scale), a.max_score)
        {Decimal.mult(normalized, a.weight), a.weight}
      end)

    case contributions do
      [] ->
        nil

      list ->
        total = Enum.reduce(list, Decimal.new(0), fn {c, _w}, acc -> Decimal.add(acc, c) end)
        weight = Enum.reduce(list, Decimal.new(0), fn {_c, w}, acc -> Decimal.add(acc, w) end)
        if Decimal.equal?(weight, Decimal.new(0)), do: nil, else: Decimal.div(total, weight)
    end
  end

  @doc "Whether a make-up is expected: the make-up rule and an absent or excused mark."
  def makeup_pending?(marks, %GradingRules{absence: :makeup}),
    do: Enum.any?(marks, &(status(&1) in [:absent, :excused]))

  def makeup_pending?(_marks, _rules), do: false

  defp counted_score(mark, rules) do
    case {status(mark), rules.absence} do
      {:graded, _} -> [{mark.assessment_id, mark.score}]
      {:absent, :zero} -> [{mark.assessment_id, Decimal.new(0)}]
      _ -> []
    end
  end

  defp status(%{status: status}) when not is_nil(status), do: status
  defp status(%{score: nil}), do: :blank
  defp status(_mark), do: :graded

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
