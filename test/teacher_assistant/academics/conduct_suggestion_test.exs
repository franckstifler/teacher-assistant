defmodule TeacherAssistant.Academics.ConductSuggestionTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.{ConductSuggestion, SchoolLifeRules}

  @rules %SchoolLifeRules{}

  defp facts(attrs),
    do: Map.merge(%{unjustified_hours: Decimal.new(0), retards: 0, sanction_types: []}, attrs)

  test "a clean séquence keeps 20 with no deductions" do
    assert %{mark: mark, deductions: []} = ConductSuggestion.suggest(facts(%{}), @rules)
    assert Decimal.equal?(mark, 20)
  end

  test "the settings page's example: 6 h, 2 lates, 1 avertissement → 14.5" do
    %{mark: mark, deductions: deductions} =
      ConductSuggestion.suggest(
        facts(%{unjustified_hours: Decimal.new(6), retards: 2, sanction_types: [:avertissement]}),
        @rules
      )

    assert Decimal.equal?(mark, Decimal.new("14.5"))

    assert [
             %{kind: :absences, points: absences},
             %{kind: :retards, count: 2, points: lates},
             %{kind: {:sanction, :avertissement}, count: 1, points: warning}
           ] = deductions

    assert Decimal.equal?(absences, 3)
    assert Decimal.equal?(lates, Decimal.new("0.5"))
    assert Decimal.equal?(warning, 2)
  end

  test "rounds down to the nearest quarter" do
    # One 50-minute lesson: 5/6 h × 0.5 = 0.4166… → 19.5833… → 19.5
    hours = Decimal.div(Decimal.new(50), Decimal.new(60))

    %{mark: mark} = ConductSuggestion.suggest(facts(%{unjustified_hours: hours}), @rules)
    assert Decimal.equal?(mark, Decimal.new("19.5"))
  end

  test "groups sanctions by type and never goes below 0" do
    %{mark: mark, deductions: deductions} =
      ConductSuggestion.suggest(
        facts(%{sanction_types: [:blame, :exclusion_temporaire, :blame, :exclusion_temporaire]}),
        @rules
      )

    assert Decimal.equal?(mark, 0)
    assert %{count: 2} = Enum.find(deductions, &(&1.kind == {:sanction, :blame}))
  end

  test "follows the school's scale" do
    rules = %{
      @rules
      | points_per_late: Decimal.new(1),
        sanction_points: %{@rules.sanction_points | consigne: Decimal.new("0.5")}
    }

    %{mark: mark} =
      ConductSuggestion.suggest(facts(%{retards: 3, sanction_types: [:consigne]}), rules)

    assert Decimal.equal?(mark, Decimal.new("16.5"))
  end
end
