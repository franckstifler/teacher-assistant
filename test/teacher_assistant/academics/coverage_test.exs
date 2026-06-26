defmodule TeacherAssistant.Academics.CoverageTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.Coverage

  test "rate is covered/planned, capped per entry" do
    entries = [
      %{id: "e1", planned_hours: Decimal.new("2"), sequence_id: "s1"},
      %{id: "e2", planned_hours: Decimal.new("2"), sequence_id: "s1"}
    ]
    logs = [
      %{progression_entry_id: "e1", hours: Decimal.new("2")},
      %{progression_entry_id: "e2", hours: Decimal.new("3")}  # over-logged, capped to 2
    ]
    result = Coverage.summarize(entries, logs)
    assert Decimal.equal?(result.planned_hours, Decimal.new("4"))
    assert Decimal.equal?(result.covered_hours, Decimal.new("4"))
    assert result.rate == 1.0
  end

  test "zero planned gives rate 0.0" do
    assert Coverage.summarize([], []).rate == 0.0
  end
end
