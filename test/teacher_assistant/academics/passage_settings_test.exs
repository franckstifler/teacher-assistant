defmodule TeacherAssistant.Academics.PassageSettingsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Accounts, Assessment}
  alias TeacherAssistant.Academics.PassageRules
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    %{scope: scope}
  end

  defp params(overrides) do
    Map.merge(
      %{
        "passage_min" => "10",
        "rachat_min" => "9,5",
        "exclusion_below" => "7",
        "exclusion_absence_hours" => "60",
        "one_repeat_per_cycle?" => "true",
        "exclusion_on_conduct?" => "true"
      },
      overrides
    )
  end

  test "defaults are the mockup's rules", %{scope: scope} do
    rules = Assessment.passage_rules(scope)
    assert Decimal.equal?(rules.passage_min, 10)
    assert Decimal.equal?(rules.rachat_min, Decimal.new("9.5"))
    assert Decimal.equal?(rules.exclusion_below, 7)
    assert rules.exclusion_absence_hours == 60
    assert rules.one_repeat_per_cycle?
    assert rules.exclusion_on_conduct?
  end

  test "a school changes its rules; empty switches a rule off", %{scope: scope} do
    assert {:ok, _} =
             Assessment.update_passage_rules(
               scope,
               params(%{
                 "passage_min" => "10,5",
                 "rachat_min" => "",
                 "exclusion_absence_hours" => "",
                 "exclusion_on_conduct?" => "false"
               })
             )

    assert %PassageRules{
             rachat_min: nil,
             exclusion_absence_hours: nil,
             exclusion_on_conduct?: false
           } =
             rules = Assessment.passage_rules(scope)

    assert Decimal.equal?(rules.passage_min, Decimal.new("10.5"))
  end

  test "an inconsistent set is refused and nothing changes", %{scope: scope} do
    for bad <- [
          %{"rachat_min" => "11"},
          %{"exclusion_below" => "9.6"},
          %{"passage_min" => "21"},
          %{"exclusion_absence_hours" => "0"}
        ] do
      assert {:error, %Ash.Error.Invalid{}} =
               Assessment.update_passage_rules(scope, params(bad))
    end

    assert {:error, :invalid_number} =
             Assessment.update_passage_rules(scope, params(%{"passage_min" => "abc"}))

    assert {:error, :invalid_number} =
             Assessment.update_passage_rules(scope, params(%{"passage_min" => ""}))

    assert {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert Decimal.equal?(profile.passage_min, 10)
  end

  test "only the admin axis changes them", %{scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope)

    assert {:error, %Ash.Error.Forbidden{}} =
             Assessment.update_passage_rules(teacher, params(%{}))
  end
end
