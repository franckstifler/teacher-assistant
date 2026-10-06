defmodule TeacherAssistant.Academics.SchoolLifeRulesTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Academics.SchoolLifeRules

  setup do
    %{scope: scope} = setup_complete_school_fixture()
    %{scope: scope}
  end

  @blank %{
    "late_as_absence_minutes" => "",
    "justification_deadline_days" => "",
    "absence_alert_hours" => "10",
    "conduct_points_per_absence_hour" => "0,5",
    "conduct_points_per_late" => "0.25",
    "sanction_points" => %{
      "consigne" => "1",
      "avertissement" => "2",
      "blame" => "4",
      "exclusion_temporaire" => "6",
      "exclusion_definitive" => "0"
    },
    "sanction_types_in_use" =>
      ~w(consigne avertissement blame exclusion_temporaire exclusion_definitive)
  }

  test "defaults", %{scope: scope} do
    rules = Attendance.school_life_rules(scope)
    assert rules.late_as_absence_minutes == nil
    assert rules.justification_deadline_days == nil
    assert rules.absence_alert_hours == 10
    assert Decimal.equal?(rules.points_per_absence_hour, Decimal.new("0.5"))
    assert Decimal.equal?(rules.points_per_late, Decimal.new("0.25"))
    assert Decimal.equal?(rules.sanction_points[:blame], Decimal.new(4))
    assert Decimal.equal?(rules.sanction_points[:exclusion_definitive], Decimal.new(0))

    assert Enum.sort(rules.sanction_types_in_use) ==
             Enum.sort(TeacherAssistant.Academics.SanctionType.values())

    # 20 − 6 × 0.5 − 2 × 0.25 − 2
    assert Decimal.equal?(SchoolLifeRules.example_mark(rules), Decimal.new("14.5"))
  end

  test "the SG saves the settings; blank optional fields mean never / any time", %{scope: scope} do
    sg = member_scope_fixture(scope, %{roles: [:discipline_master]})
    assert Attendance.can_edit_school_life?(sg)

    params =
      @blank
      |> Map.merge(%{
        "late_as_absence_minutes" => "15",
        "justification_deadline_days" => "2",
        "absence_alert_hours" => "8",
        "conduct_points_per_late" => "0,5"
      })
      |> put_in(["sanction_points", "blame"], "5")
      |> Map.put("sanction_types_in_use", ~w(consigne avertissement blame))

    assert {:ok, _} = Attendance.update_school_life_rules(sg, params)
    rules = Attendance.school_life_rules(scope)
    assert rules.late_as_absence_minutes == 15
    assert rules.justification_deadline_days == 2
    assert rules.absence_alert_hours == 8
    assert Decimal.equal?(rules.points_per_late, Decimal.new("0.5"))
    assert Decimal.equal?(rules.sanction_points[:blame], Decimal.new(5))
    # Kept in the enum's own order.
    assert rules.sanction_types_in_use == [:avertissement, :blame, :consigne]

    assert {:ok, _} = Attendance.update_school_life_rules(sg, @blank)
    rules = Attendance.school_life_rules(scope)
    assert rules.late_as_absence_minutes == nil
    assert rules.justification_deadline_days == nil
  end

  test "bad input is refused", %{scope: scope} do
    assert {:error, :invalid_number} =
             Attendance.update_school_life_rules(scope, %{@blank | "absence_alert_hours" => "dix"})

    assert {:error, :invalid_number} =
             Attendance.update_school_life_rules(scope, %{@blank | "absence_alert_hours" => ""})

    assert {:error, :no_sanction_type} =
             Attendance.update_school_life_rules(
               scope,
               Map.delete(@blank, "sanction_types_in_use")
             )

    assert {:error, %Ash.Error.Invalid{}} =
             Attendance.update_school_life_rules(scope, %{
               @blank
               | "late_as_absence_minutes" => "500"
             })

    assert Attendance.school_life_rules(scope).absence_alert_hours == 10
  end

  test "a plain teacher may not change them", %{scope: scope} do
    teacher = member_scope_fixture(scope, %{roles: [:teacher]})
    refute Attendance.can_edit_school_life?(teacher)
    assert_forbidden(Attendance.update_school_life_rules(teacher, @blank))
  end
end
