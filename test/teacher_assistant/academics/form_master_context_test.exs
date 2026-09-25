defmodule TeacherAssistant.Academics.FormMasterContextTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization

  setup do
    user = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, school} = Organization.create_school(user, %{name: "Lycée FMC"})

    {:ok, year} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} =
      Enrollment.create_class_group(school_scope(user, school), year, %{
        label: "6e A",
        level: "6ème"
      })

    {:ok, cg2} =
      Enrollment.create_class_group(school_scope(user, school), year, %{
        label: "6e B",
        level: "6ème"
      })

    %{user: user, school: school, scope: school_scope(user, school), year: year, cg: cg, cg2: cg2}
  end

  test "set_form_master sets, resolves, and lists", ctx do
    %{user: user, year: year, cg: cg, scope: scope} = ctx
    {:ok, cg} = Enrollment.set_form_master(scope, cg, user.id)
    assert cg.form_master_user_id == user.id
    assert Enrollment.form_master(scope, cg).id == user.id

    classes = Enrollment.list_form_master_classes(scope, year)
    assert Enum.map(classes, & &1.id) == [cg.id]
  end

  test "set_form_master with nil clears it", %{user: user, cg: cg, scope: scope} do
    {:ok, cg} = Enrollment.set_form_master(scope, cg, user.id)
    {:ok, cg} = Enrollment.set_form_master(scope, cg, nil)
    assert cg.form_master_user_id == nil
    assert Enrollment.form_master(scope, cg) == nil
  end

  test "list_form_master_classes excludes classes of other form masters", ctx do
    %{user: user, year: year, cg: cg, cg2: cg2, scope: scope} = ctx
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    TeacherAssistant.TeacherFixtures.membership_fixture(school_scope(user, ctx.school), %{
      user: other
    })

    {:ok, _} = Enrollment.set_form_master(scope, cg, user.id)
    {:ok, _} = Enrollment.set_form_master(scope, cg2, other.id)
    assert Enum.map(Enrollment.list_form_master_classes(scope, year), & &1.id) == [cg.id]
  end
end
