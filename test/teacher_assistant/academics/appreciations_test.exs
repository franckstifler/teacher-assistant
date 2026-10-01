defmodule TeacherAssistant.Academics.AppreciationsTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Academics.{Appreciations, GradingRules}

  defp d(n), do: Decimal.new(n)
  defp label(avg, rules \\ %GradingRules{}), do: Appreciations.appreciation(d(avg), rules).label

  describe "appreciation/2 with the default bands" do
    test "each band starts at its lower bound; 20 is in the last band" do
      assert label("0") == "Très insuffisant"
      assert label("4.99") == "Très insuffisant"
      assert label("5") == "Insuffisant"
      assert label("8") == "Médiocre"
      assert label("9.99") == "Médiocre"
      assert label("10") == "Passable"
      assert label("12") == "Assez bien"
      assert label("14") == "Bien"
      assert label("16") == "Très bien"
      assert label("18") == "Excellent"
      assert label("20") == "Excellent"
    end

    test "nil average has no appreciation; passed? is average >= 10" do
      assert Appreciations.appreciation(nil, %GradingRules{}) == nil

      assert %{passed?: false, position: 2} =
               Appreciations.appreciation(d("9.5"), %GradingRules{})

      assert %{passed?: true, position: 3} = Appreciations.appreciation(d("10"), %GradingRules{})
    end

    test "default labels follow the locale" do
      Gettext.with_locale(TeacherAssistantWeb.Gettext, "en", fn ->
        assert label("13") == "Fairly good"
      end)
    end
  end

  test "a school's own bands are used as typed" do
    rules = %GradingRules{
      appreciation_bands: [%{from: d("0"), label: "Faible"}, %{from: d("11"), label: "Solide"}]
    }

    assert label("10.99", rules) == "Faible"
    assert label("11", rules) == "Solide"
    assert label("20", rules) == "Solide"

    Gettext.with_locale(TeacherAssistantWeb.Gettext, "en", fn ->
      assert label("15", rules) == "Solide"
    end)
  end

  describe "distinction/4" do
    test "highest honour roll wins, at the default thresholds" do
      r = %GradingRules{}
      assert Appreciations.distinction(d("16"), [d("16")], nil, r) == :felicitations
      assert Appreciations.distinction(d("15.99"), [d("15.99")], nil, r) == :encouragements
      assert Appreciations.distinction(d("12"), [d("12")], nil, r) == :tableau_honneur
      assert Appreciations.distinction(d("11.99"), [d("11.99")], nil, r) == nil
      assert Appreciations.distinction(nil, [], nil, r) == nil
    end

    test "work warnings: blâme below 6, avertissement below 8, no gate" do
      r = %GradingRules{}
      assert Appreciations.distinction(d("5.99"), [d("5.99")], d("18"), r) == :blame_travail
      assert Appreciations.distinction(d("6"), [d("6")], nil, r) == :avertissement_travail
      assert Appreciations.distinction(d("7.99"), [nil], nil, r) == :avertissement_travail
      assert Appreciations.distinction(d("8"), [d("8")], nil, r) == nil
    end

    test "all-subjects gate: a subject under 10 blocks honours unless the gate is off" do
      subjects = [d("18"), d("9")]
      assert Appreciations.distinction(d("16"), subjects, nil, %GradingRules{}) == nil

      off = %GradingRules{distinctions_require_all_passed?: false}
      assert Appreciations.distinction(d("16"), subjects, nil, off) == :felicitations
      # ungraded subjects never block
      assert Appreciations.distinction(d("16"), [d("16"), nil], nil, %GradingRules{}) ==
               :felicitations
    end

    test "conduct gate: below 12 blocks, missing conduct does not" do
      on = %GradingRules{distinctions_require_conduct?: true}
      assert Appreciations.distinction(d("17"), [d("17")], d("11.5"), on) == nil
      assert Appreciations.distinction(d("17"), [d("17")], d("12"), on) == :felicitations
      assert Appreciations.distinction(d("17"), [d("17")], nil, on) == :felicitations
      # the conduct gate is ignored when off
      assert Appreciations.distinction(d("17"), [d("17")], d("3"), %GradingRules{}) ==
               :felicitations
    end

    test "a nil threshold switches that distinction off" do
      r = %GradingRules{felicitations_min: nil, blame_travail_below: nil}
      assert Appreciations.distinction(d("19"), [d("19")], nil, r) == :encouragements
      assert Appreciations.distinction(d("2"), [d("2")], nil, r) == :avertissement_travail

      all_off = %GradingRules{
        felicitations_min: nil,
        encouragements_min: nil,
        tableau_honneur_min: nil,
        avertissement_travail_below: nil,
        blame_travail_below: nil
      }

      assert Appreciations.distinction(d("19"), [d("19")], nil, all_off) == nil
      assert Appreciations.distinction(d("1"), [d("1")], nil, all_off) == nil
    end
  end
end
