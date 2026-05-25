defmodule TeacherAssistant.Academics.ReportCardsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics.ReportCards

  describe "summarize_student/1" do
    test "computes weighted average from marks and coefficients" do
      summary =
        ReportCards.summarize_student([
          %{subject: "Mathematics", score: Decimal.new("16"), coefficient: 5},
          %{subject: "English", score: Decimal.new("12"), coefficient: 3}
        ])

      assert summary.total_coefficient == 8
      assert Decimal.equal?(summary.weighted_total, Decimal.new("116"))
      assert Decimal.equal?(summary.average, Decimal.new("14.50"))
    end

    test "ignores missing marks but keeps missing count" do
      summary =
        ReportCards.summarize_student([
          %{subject: "Mathematics", score: Decimal.new("16"), coefficient: 5},
          %{subject: "English", score: nil, coefficient: 3}
        ])

      assert summary.missing_marks == 1
      assert summary.total_coefficient == 5
      assert Decimal.equal?(summary.average, Decimal.new("16.00"))
    end
  end

  describe "rank_students/1" do
    test "assigns the same rank to tied averages" do
      ranked =
        ReportCards.rank_students([
          %{student_id: "a", average: Decimal.new("15.00")},
          %{student_id: "b", average: Decimal.new("17.00")},
          %{student_id: "c", average: Decimal.new("15.00")}
        ])

      assert Enum.map(ranked, &{&1.student_id, &1.rank}) == [{"b", 1}, {"a", 2}, {"c", 2}]
    end
  end
end
