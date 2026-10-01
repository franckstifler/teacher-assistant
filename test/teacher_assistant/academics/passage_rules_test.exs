defmodule TeacherAssistant.Academics.PassageRulesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.PassageRules

  defp d(n), do: Decimal.new(n)

  defp propose(avg, opts \\ [], rules \\ %PassageRules{}) do
    PassageRules.propose(
      %{
        average: avg && d(avg),
        repeater?: Keyword.get(opts, :repeater?, false),
        conduct: opts[:conduct] && d(opts[:conduct]),
        unjustified_hours: opts[:hours] && d(opts[:hours])
      },
      rules
    )
  end

  test "averages: passing, rachat, repeat, exclusion — each threshold included" do
    assert propose("10") == {:admis, nil}
    assert propose("15") == {:admis, nil}
    assert propose("9.99") == {:admis_rachat, nil}
    assert propose("9.5") == {:admis_rachat, nil}
    assert propose("9.49") == {:redouble, nil}
    assert propose("7") == {:redouble, nil}
    assert propose("6.99") == {:exclu, "Moyenne < 7"}
    assert propose(nil) == nil
  end

  test "a nil threshold switches its rule off" do
    assert propose("9.6", [], %PassageRules{rachat_min: nil}) == {:redouble, nil}
    assert propose("2", [], %PassageRules{exclusion_below: nil}) == {:redouble, nil}
  end

  test "one repeat per cycle" do
    assert propose("8", repeater?: true) == {:exclu, "Déjà redoublant"}
    assert propose("12", repeater?: true) == {:admis, nil}

    assert propose("8", [repeater?: true], %PassageRules{one_repeat_per_cycle?: false}) ==
             {:redouble, nil}
  end

  test "conduct below 10 excludes, missing conduct does not" do
    assert propose("15", conduct: "9.5") == {:exclu, "Conduite < 10"}
    assert propose("15", conduct: "10") == {:admis, nil}
    assert propose("15") == {:admis, nil}

    assert propose("15", [conduct: "3"], %PassageRules{exclusion_on_conduct?: false}) ==
             {:admis, nil}
  end

  test "unjustified absences at the limit exclude" do
    assert propose("15", hours: "60") == {:exclu, "60 h d'absences non justifiées"}
    assert propose("15", hours: "59.5") == {:admis, nil}

    assert propose("15", [hours: "200"], %PassageRules{exclusion_absence_hours: nil}) ==
             {:admis, nil}
  end
end
