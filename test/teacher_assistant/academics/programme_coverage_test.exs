defmodule TeacherAssistant.Academics.ProgrammeCoverageTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics.ProgrammeCoverage

  test "computes coverage from planned and taught hours" do
    coverage =
      ProgrammeCoverage.summarize([
        %{planned_hours: Decimal.new("4"), taught_hours: Decimal.new("4")},
        %{planned_hours: Decimal.new("2"), taught_hours: Decimal.new("1")}
      ])

    assert Decimal.equal?(coverage.planned_hours, Decimal.new("6"))
    assert Decimal.equal?(coverage.taught_hours, Decimal.new("5"))
    assert Decimal.equal?(coverage.rate, Decimal.new("83.33"))
  end

  test "returns zero coverage when no hours are planned" do
    coverage = ProgrammeCoverage.summarize([])

    assert Decimal.equal?(coverage.planned_hours, Decimal.new("0"))
    assert Decimal.equal?(coverage.taught_hours, Decimal.new("0"))
    assert Decimal.equal?(coverage.rate, Decimal.new("0.00"))
  end
end
