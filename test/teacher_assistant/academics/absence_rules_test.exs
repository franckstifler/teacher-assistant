defmodule TeacherAssistant.Academics.AbsenceRulesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.{GradingRules, Marks}

  defp d(x), do: Decimal.new(x)
  @w %{
    "a" => %{weight: Decimal.new(1), max_score: Decimal.new(20)},
    "b" => %{weight: Decimal.new(1), max_score: Decimal.new(20)}
  }

  defp marks(b_status),
    do: [
      %{assessment_id: "a", score: d(14), status: :graded},
      %{assessment_id: "b", score: nil, status: b_status}
    ]

  test "absent counts as zero only under the zero rule" do
    assert Decimal.equal?(
             Marks.subject_average(marks(:absent), @w, %GradingRules{absence: :zero}),
             7
           )

    assert Decimal.equal?(
             Marks.subject_average(marks(:absent), @w, %GradingRules{absence: :excluded}),
             14
           )

    assert Decimal.equal?(
             Marks.subject_average(marks(:absent), @w, %GradingRules{absence: :makeup}),
             14
           )
  end

  test "excused is always left out" do
    for rule <- [:zero, :excluded, :makeup] do
      assert Decimal.equal?(
               Marks.subject_average(marks(:excused), @w, %GradingRules{absence: rule}),
               14
             )
    end
  end

  test "an absence alone under the zero rule gives 0, otherwise no average" do
    only = [%{assessment_id: "a", score: nil, status: :absent}]
    assert Decimal.equal?(Marks.subject_average(only, @w, %GradingRules{absence: :zero}), 0)
    assert Marks.subject_average(only, @w, %GradingRules{absence: :excluded}) == nil
  end

  test "marks without a status keep working (graded when scored)" do
    assert Decimal.equal?(Marks.subject_average([%{assessment_id: "a", score: d(12)}], @w), 12)
  end

  test "make-ups are pending only under the make-up rule, for absent or excused" do
    makeup = %GradingRules{absence: :makeup}
    assert Marks.makeup_pending?(marks(:absent), makeup)
    assert Marks.makeup_pending?(marks(:excused), makeup)
    refute Marks.makeup_pending?(marks(:absent), %GradingRules{absence: :zero})
    refute Marks.makeup_pending?([%{assessment_id: "a", score: d(1), status: :graded}], makeup)
  end
end
