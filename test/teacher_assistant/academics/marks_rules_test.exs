defmodule TeacherAssistant.Academics.MarksRulesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.{GradingRules, Marks}

  test "the subject summary rounds averages and follows the rank rule" do
    students = [%{id: "a", sex: :f, name: "Awa"}, %{id: "b", sex: :m, name: "Bob"}]
    assessments = [%{id: "x", weight: Decimal.new(1), max_score: Decimal.new(20)}]

    marks = [
      %{assessment_id: "x", student_id: "a", score: Decimal.new("13.12")},
      %{assessment_id: "x", student_id: "b", score: Decimal.new("12.9")}
    ]

    rules = %GradingRules{rounding: :quarter, shared_ranks?: false}
    s = Marks.summarize(students, assessments, marks, rules)
    assert Decimal.equal?(s.per_student["a"].average, Decimal.new(13))
    assert s.per_student["a"].rank == 1 and s.per_student["b"].rank == 2
  end
end
