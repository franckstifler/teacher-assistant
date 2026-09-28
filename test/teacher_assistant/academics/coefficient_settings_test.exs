defmodule TeacherAssistant.Academics.CoefficientSettingsTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Accounts, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head} = TeacherFixtures.school_fixture()

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Mathématiques"})
    %{scope: scope, tc: tc}
  end

  test "defaults: class overrides allowed, no group subtotals", %{scope: scope} do
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.class_coefficients_allowed?
    refute profile.bulletin_group_subtotals?
  end

  test "overrides cannot be switched off while a class has one", %{scope: scope, tc: tc} do
    {:ok, _} = Curriculum.set_assignment_coefficient(scope, tc, "3")
    assert {:error, {:overrides_exist, ["6e A"]}} = Curriculum.set_class_coefficients_allowed(scope, false)

    {:ok, _} = Curriculum.clear_assignment_coefficient(scope, tc)
    assert {:ok, %{class_coefficients_allowed?: false}} = Curriculum.set_class_coefficients_allowed(scope, false)
  end

  test "with overrides off, a class coefficient cannot be set", %{scope: scope, tc: tc} do
    {:ok, _} = Curriculum.set_class_coefficients_allowed(scope, false)
    assert {:error, :class_coefficients_disabled} = Curriculum.set_assignment_coefficient(scope, tc, "3")
  end

  test "group subtotals can be switched on", %{scope: scope} do
    assert {:ok, %{bulletin_group_subtotals?: true}} = Curriculum.set_bulletin_group_subtotals(scope, true)
  end

  test "a teacher cannot change these settings", %{scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope)
    assert_forbidden(Curriculum.set_bulletin_group_subtotals(teacher, true))
  end
end
