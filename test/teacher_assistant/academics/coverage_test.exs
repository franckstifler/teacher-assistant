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
      # over-logged, capped to 2
      %{progression_entry_id: "e2", hours: Decimal.new("3")}
    ]

    result = Coverage.summarize(entries, logs)
    assert Decimal.equal?(result.planned_hours, Decimal.new("4"))
    assert Decimal.equal?(result.covered_hours, Decimal.new("4"))
    assert result.rate == 1.0
  end

  test "zero planned gives rate 0.0" do
    assert Coverage.summarize([], []).rate == 0.0
  end

  test "a completed entry counts as fully covered regardless of logs" do
    entries = [
      %{id: "e1", planned_hours: Decimal.new("3"), sequence_id: "s1", completed?: true},
      %{id: "e2", planned_hours: Decimal.new("2"), sequence_id: "s1", completed?: false}
    ]

    # e1 has NO log yet is completed → covered 3; e2 logged 1 → covered 1
    logs = [%{progression_entry_id: "e2", hours: Decimal.new("1")}]

    result = Coverage.summarize(entries, logs)
    assert Decimal.equal?(result.covered_hours, Decimal.new("4"))
    pe1 = Enum.find(result.per_entry, &(&1.entry_id == "e1"))
    assert Decimal.equal?(pe1.covered, Decimal.new("3"))
  end

  test "completed does not exceed planned even with over-logging" do
    entries = [%{id: "e1", planned_hours: Decimal.new("2"), sequence_id: nil, completed?: true}]
    logs = [%{progression_entry_id: "e1", hours: Decimal.new("5")}]
    result = Coverage.summarize(entries, logs)
    assert Decimal.equal?(result.covered_hours, Decimal.new("2"))
  end
end
