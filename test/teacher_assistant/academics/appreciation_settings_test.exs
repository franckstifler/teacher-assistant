defmodule TeacherAssistant.Academics.AppreciationSettingsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Accounts, Assessment, Curriculum, Discipline, Enrollment, Organization}
  alias TeacherAssistant.Academics.{Appreciations, GradingRules}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()
    %{scope: scope, head: head}
  end

  defp band(from, label), do: %{from: from, label: label}

  test "defaults: no saved scale, official thresholds", %{scope: scope} do
    rules = Assessment.grading_rules(scope)
    assert rules.appreciation_bands in [nil, []]
    assert Appreciations.bands(rules) |> length() == 8
    assert Decimal.equal?(rules.felicitations_min, 16)
    assert Decimal.equal?(rules.blame_travail_below, 6)
    assert rules.distinctions_require_all_passed?
    refute rules.distinctions_require_conduct?
  end

  test "a school saves its own bands, comma decimals accepted", %{scope: scope} do
    assert {:ok, _} =
             Assessment.update_appreciation_bands(scope, [
               band("0", "Faible"),
               band("9,5", " Moyen "),
               band("15", "Fort")
             ])

    rules = Assessment.grading_rules(scope)
    assert [%{label: "Faible"}, %{label: "Moyen"}, %{label: "Fort"}] = Appreciations.bands(rules)
    assert Appreciations.appreciation(Decimal.new("9.5"), rules).label == "Moyen"

    assert {:ok, _} = Assessment.reset_appreciation_bands(scope)
    assert Assessment.grading_rules(scope) |> Appreciations.bands() |> length() == 8
  end

  test "invalid bands are refused and nothing changes", %{scope: scope} do
    assert {:error, :invalid_number} =
             Assessment.update_appreciation_bands(scope, [band("0", "A"), band("abc", "B")])

    for bad <- [
          [band("1", "A")],
          [band("0", "A"), band("12", "B"), band("10", "C")],
          [band("0", "A"), band("10", "B"), band("10", "C")],
          [band("0", "A"), band("21", "B")],
          [band("0", "A"), band("10", "  ")]
        ] do
      assert {:error, %Ash.Error.Invalid{}} = Assessment.update_appreciation_bands(scope, bad)
    end

    assert {:ok, %{appreciation_bands: bands}} = Accounts.fetch_school_profile(scope)
    assert bands in [nil, []]
  end

  test "thresholds: empty switches off, order is enforced", %{scope: scope} do
    params = %{
      "felicitations_min" => "17",
      "encouragements_min" => "14,5",
      "tableau_honneur_min" => "12",
      "avertissement_travail_below" => "",
      "blame_travail_below" => "5",
      "distinctions_require_all_passed?" => "false",
      "distinctions_require_conduct?" => "true"
    }

    assert {:ok, _} = Assessment.update_distinction_rules(scope, params)

    assert %GradingRules{
             avertissement_travail_below: nil,
             distinctions_require_all_passed?: false,
             distinctions_require_conduct?: true
           } = rules = Assessment.grading_rules(scope)

    assert Decimal.equal?(rules.encouragements_min, Decimal.new("14.5"))

    assert {:error, %Ash.Error.Invalid{}} =
             Assessment.update_distinction_rules(scope, %{params | "encouragements_min" => "18"})

    assert {:error, %Ash.Error.Invalid{}} =
             Assessment.update_distinction_rules(scope, %{
               params
               | "avertissement_travail_below" => "4"
             })

    assert {:error, %Ash.Error.Invalid{}} =
             Assessment.update_distinction_rules(scope, %{params | "tableau_honneur_min" => "25"})

    assert {:error, :invalid_number} =
             Assessment.update_distinction_rules(scope, %{params | "felicitations_min" => "x"})

    assert Decimal.equal?(Assessment.grading_rules(scope).felicitations_min, 17)
  end

  test "every threshold empty: no distinction at all, no crash", %{scope: scope} do
    empty =
      Map.new(
        ~w(felicitations_min encouragements_min tableau_honneur_min avertissement_travail_below blame_travail_below),
        &{&1, ""}
      )

    assert {:ok, _} = Assessment.update_distinction_rules(scope, empty)
    rules = Assessment.grading_rules(scope)
    assert Appreciations.distinction(Decimal.new(19), [], nil, rules) == nil
  end

  test "the conduct gate reads the period's note de conduite" do
    %{scope: scope, head_user: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e G", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bella", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Chantal", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Diane", sex: :f})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(1)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{
        label: "D",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    roster = Enrollment.list_roster(scope, cg)

    :ok =
      Assessment.upsert_marks(
        scope,
        a,
        Enum.map(roster, &%{student_id: &1.student.id, score: Decimal.new(17)})
      )

    [bella, chantal, _diane] = roster
    {:ok, _} = Discipline.set_conduct_mark(scope, bella.enrollment, seq, "10")
    {:ok, _} = Discipline.set_conduct_mark(scope, chantal.enrollment, seq, "15")

    {:ok, _} =
      Assessment.update_distinction_rules(scope, %{
        "felicitations_min" => "16",
        "encouragements_min" => "14",
        "tableau_honneur_min" => "12",
        "avertissement_travail_below" => "8",
        "blame_travail_below" => "6",
        "distinctions_require_all_passed?" => "true",
        "distinctions_require_conduct?" => "true"
      })

    r = Assessment.class_results_for_period(scope, cg, {:sequence, seq})
    by_name = Map.new(roster, &{&1.student.full_name, r.per_student[&1.student.id].distinction})
    assert by_name == %{"Bella" => nil, "Chantal" => :felicitations, "Diane" => :felicitations}
  end
end
