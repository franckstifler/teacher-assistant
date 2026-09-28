defmodule TeacherAssistant.Academics.GradingRulesTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.GradingRules

  defp d(x), do: Decimal.new(x)
  defp rules(attrs), do: struct(GradingRules, attrs)

  test "rounding modes are half-up; :none leaves the value untouched" do
    assert GradingRules.round_average(d("13.125"), rules(rounding: :hundredth)) == d("13.13")
    assert GradingRules.round_average(d("13.25"), rules(rounding: :tenth)) == d("13.3")

    assert Decimal.equal?(
             GradingRules.round_average(d("13.125"), rules(rounding: :quarter)),
             d("13.25")
           )

    assert Decimal.equal?(
             GradingRules.round_average(d("13.12"), rules(rounding: :quarter)),
             d("13")
           )

    assert Decimal.equal?(
             GradingRules.round_average(d("13.375"), rules(rounding: :quarter)),
             d("13.5")
           )

    assert GradingRules.round_average(d("13.1234"), %GradingRules{}) == d("13.1234")
    assert GradingRules.round_average(nil, rules(rounding: :tenth)) == nil
  end

  test "trimester: plain mean, or the second séquence counted twice" do
    plain = rules(rounding: :hundredth)
    double = rules(trimester: :second_sequence_double, rounding: :hundredth)

    assert Decimal.equal?(
             GradingRules.trimester_average([{1, d(12)}, {2, d(15)}], plain),
             d("13.5")
           )

    assert Decimal.equal?(GradingRules.trimester_average([{1, d(12)}, {2, d(15)}], double), d(14))
  end

  test "a missing séquence is skipped with its weight" do
    double = rules(trimester: :second_sequence_double)
    assert Decimal.equal?(GradingRules.trimester_average([{1, nil}, {2, d(15)}], double), d(15))
    assert Decimal.equal?(GradingRules.trimester_average([{1, d(12)}, {2, nil}], double), d(12))
    assert GradingRules.trimester_average([{1, nil}, {2, nil}], double) == nil
  end

  test "annual: mean of the séquences, or mean of the trimesters; missing ones skipped" do
    terms = [
      {1, [{1, d(10)}, {2, nil}]},
      {2, [{1, d(14)}, {2, d(16)}]},
      {3, [{1, nil}, {2, nil}]}
    ]

    # séquences: (10 + 14 + 16) / 3 = 13.333… → 13.33
    assert Decimal.equal?(
             GradingRules.annual_average(terms, rules(rounding: :hundredth)),
             d("13.33")
           )

    # trimesters: T1 = 10, T2 = 15, T3 absent → 12.5
    by_terms = rules(annual: :mean_of_trimesters, rounding: :hundredth)
    assert Decimal.equal?(GradingRules.annual_average(terms, by_terms), d("12.5"))
  end

  test "shared ranks: equal averages share a rank" do
    entries = [
      %{id: "a", average: d(15), precise: d("15.004"), name: "Zoé"},
      %{id: "b", average: d(15), precise: d("14.996"), name: "Awa"},
      %{id: "c", average: d(12), precise: d(12), name: "Bob"},
      %{id: "x", average: nil, precise: nil, name: "Nul"}
    ]

    assert GradingRules.ranks(entries, %GradingRules{}) == %{"a" => 1, "b" => 1, "c" => 3}
  end

  test "without shared ranks, the unrounded average then the name break ties" do
    entries = [
      %{id: "a", average: d(15), precise: d("14.996"), name: "Awa"},
      %{id: "b", average: d(15), precise: d("15.004"), name: "Zoé"},
      %{id: "c", average: d(12), precise: d(12), name: "Mia"},
      %{id: "d", average: d(12), precise: d(12), name: "Bob"}
    ]

    assert GradingRules.ranks(entries, rules(shared_ranks?: false)) ==
             %{"b" => 1, "a" => 2, "d" => 3, "c" => 4}
  end

  test "unrounded period means are available for tie-breaks" do
    double = rules(trimester: :second_sequence_double, rounding: :quarter)

    assert Decimal.equal?(
             GradingRules.trimester_mean([{1, d("12.1")}, {2, d(14)}], double),
             Decimal.div(d("40.1"), 3)
           )

    by_terms = rules(annual: :mean_of_trimesters, rounding: :quarter)
    terms = [{1, [{1, d(10)}, {2, d(11)}]}, {2, [{1, d(14)}, {2, nil}]}]
    # T1 = 10.5 (quarter) ; T2 = 14 → unrounded annual 12.25
    assert Decimal.equal?(GradingRules.annual_mean(terms, by_terms), d("12.25"))
  end
end
