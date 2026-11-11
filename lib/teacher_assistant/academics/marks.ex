defmodule TeacherAssistant.Academics.Marks do
  @moduledoc """
  Pure, deterministic per-subject mark statistics (Francophone /20).
  No database access — operates on plain maps, like `Academics.Coverage`.
  """

  alias TeacherAssistant.Academics.{Appreciations, GradingRules}

  @pass Decimal.new(10)
  @scale Decimal.new(20)

  @doc "The appreciation of a /20 average under the school's scale (`Academics.Appreciations`)."
  def mention(avg, rules \\ %GradingRules{}), do: Appreciations.appreciation(avg, rules)

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

    from_averages(students, precise, rules)
  end

  @doc """
  The summary `summarize/4` returns, from each student's subject average for the
  period (`%{student_id => Decimal | nil}`): rounded by the school's rule, ranked
  (rounding ties broken by the given value), with the class and per-sex figures.
  The trimester and annual statistics pass the bulletin's subject averages, so the
  figures are the bulletin's (spec audit follow-ups A4).
  """
  def from_averages(students, averages, rules \\ %GradingRules{}) do
    ranks =
      students
      |> Enum.map(fn s ->
        precise = Map.get(averages, s.id)

        %{
          id: s.id,
          average: GradingRules.round_average(precise, rules),
          precise: precise,
          name: Map.get(s, :name, "")
        }
      end)
      |> GradingRules.ranks(rules)

    per_student =
      Map.new(students, fn s ->
        avg = GradingRules.round_average(Map.get(averages, s.id), rules)
        {s.id, %{average: avg, mention: mention(avg, rules), rank: ranks[s.id]}}
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

  @bands [
    {"0 – 5", 0, 5},
    {"5 – 10", 5, 10},
    {"10 – 12", 10, 12},
    {"12 – 15", 12, 15},
    {"15 – 20", 15, 21}
  ]

  @doc """
  Counts of /20 averages per results band (spec 2026-10-09 §1.3): lower bound
  inclusive, 20 in the last band, nils ignored.
  """
  def distribution(averages) do
    graded = Enum.reject(averages, &is_nil/1)

    Enum.map(@bands, fn {label, low, high} ->
      %{
        label: label,
        below_pass?: high <= 10,
        count:
          Enum.count(
            graded,
            &(Decimal.compare(&1, low) != :lt and Decimal.compare(&1, high) == :lt)
          )
      }
    end)
  end
end
