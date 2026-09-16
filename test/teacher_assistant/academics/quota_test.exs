defmodule TeacherAssistant.Academics.QuotaTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.Quota

  defp entry(hours, type \\ :lesson),
    do: %{planned_hours: Decimal.new(hours), entry_type: type}

  defp mod(id, default?, credit, entries),
    do: %{id: id, default?: default?, credit_hours: credit, entries: entries}

  test "summarizes context and per-module gaps, excluding default bucket and non-lessons" do
    ctx = %{annual_hours: Decimal.new("100"), target_module_count: 2, target_lesson_count: 3}

    modules = [
      mod("m1", false, Decimal.new("40"), [entry("20"), entry("10"), entry("2", :evaluation)]),
      mod("m2", false, nil, [entry("15")]),
      mod("bucket", true, nil, [entry("3", :lesson), entry("1", :holiday)])
    ]

    q = Quota.summarize(ctx, modules)

    assert Decimal.equal?(q.planned_hours, Decimal.new("51"))
    assert Decimal.equal?(q.annual_hours, Decimal.new("100"))
    assert_in_delta q.hours_ratio, 0.51, 0.0001
    # default bucket excluded from module count
    assert q.module_count == 2
    assert q.target_module_count == 2

    # lessons only: 20,10 (m1) + 15 (m2) + 3 (bucket lesson) = 4 lessons; evaluation & holiday excluded
    assert q.lesson_count == 4
    assert q.target_lesson_count == 3

    m1 = Enum.find(q.per_module, &(&1.module_id == "m1"))
    assert Decimal.equal?(m1.planned, Decimal.new("32"))
    assert Decimal.equal?(m1.credit, Decimal.new("40"))
    assert_in_delta m1.ratio, 0.8, 0.0001

    m2 = Enum.find(q.per_module, &(&1.module_id == "m2"))
    assert m2.credit == nil
    assert m2.ratio == nil
  end

  test "nil context yields nil targets and nil ratios, planned still computed" do
    modules = [
      %{
        id: "m1",
        default?: false,
        credit_hours: nil,
        entries: [%{planned_hours: Decimal.new("5"), entry_type: :lesson}]
      }
    ]

    q = Quota.summarize(nil, modules)
    assert Decimal.equal?(q.planned_hours, Decimal.new("5"))
    assert q.annual_hours == nil
    assert q.hours_ratio == nil
    assert q.target_module_count == nil
    assert q.module_count == 1
  end
end
