defmodule TeacherAssistant.Academics.GradingSettingsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Accounts, Assessment}
  alias TeacherAssistant.Academics.GradingRules
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.school_fixture()
    %{scope: scope}
  end

  test "defaults are the official rules, rounded to the hundredth, shared ranks", %{scope: scope} do
    assert Assessment.grading_rules(scope) == %GradingRules{
             trimester: :mean_of_sequences,
             annual: :mean_of_sequences,
             rounding: :hundredth,
             shared_ranks?: true
           }
  end

  test "an admin changes the rules", %{scope: scope} do
    assert {:ok, _} =
             Assessment.update_grading_rules(scope, %{
               "trimester_average_rule" => "second_sequence_double",
               "annual_average_rule" => "mean_of_trimesters",
               "average_rounding" => "quarter",
               "shared_ranks?" => "false"
             })

    assert %GradingRules{
             trimester: :second_sequence_double,
             annual: :mean_of_trimesters,
             rounding: :quarter,
             shared_ranks?: false
           } = Assessment.grading_rules(scope)
  end

  test "an unknown field or value is refused and nothing changes", %{scope: scope} do
    assert {:error, :invalid_rule} =
             Assessment.update_grading_rules(scope, %{"average_rounding" => "thousandth"})

    assert {:error, :invalid_rule} = Assessment.update_grading_rules(scope, %{"name" => "Hacked"})
    assert {:ok, %{average_rounding: :hundredth}} = Accounts.fetch_school_profile(scope)
  end

  test "a teacher cannot change the rules", %{scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope)
    assert_forbidden(Assessment.update_grading_rules(teacher, %{"average_rounding" => "tenth"}))
  end
end
