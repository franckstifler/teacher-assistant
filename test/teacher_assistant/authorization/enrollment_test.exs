defmodule TeacherAssistant.Authorization.EnrollmentTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Enrollment, Scope}

  setup do
    %{workspace: ws, year: year, scope: head} = setup_complete_school_fixture()
    [cg, other_cg | _] = Enrollment.list_class_groups(head, year)
    fm = member_scope_fixture(head, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(head, cg, fm.current_user.id)
    teacher = member_scope_fixture(head, %{roles: [:teacher]})
    outsider = %Scope{current_user: user_fixture(), current_workspace: ws}

    %{
      ws: ws,
      year: year,
      head: head,
      fm: fm,
      teacher: teacher,
      outsider: outsider,
      cg: cg,
      other_cg: other_cg
    }
  end

  defp student, do: %{full_name: "Awa #{System.unique_integer([:positive])}", sex: :f}

  test "admins and the class's form master enrol; others cannot", ctx do
    assert {:ok, _} = Enrollment.enroll_new(ctx.head, ctx.cg, student())
    assert {:ok, _} = Enrollment.enroll_new(ctx.fm, ctx.cg, student())
    assert_forbidden(Enrollment.enroll_new(ctx.fm, ctx.other_cg, student()))
    assert_forbidden(Enrollment.enroll_new(ctx.teacher, ctx.cg, student()))
    assert_forbidden(Enrollment.enroll_new(ctx.outsider, ctx.cg, student()))
    assert_forbidden(Enrollment.enroll_new(%Scope{current_workspace: ctx.ws}, ctx.cg, student()))
  end

  test "a refused enroll_new leaves no orphan student", ctx do
    name = "Orphan #{System.unique_integer([:positive])}"
    assert_forbidden(Enrollment.enroll_new(ctx.teacher, ctx.cg, %{full_name: name, sex: :f}))
    assert Enrollment.search_students(ctx.head, name) == []
  end

  test "a transfer is decided by the source class", ctx do
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(ctx.head, ctx.cg, student())
    assert {:ok, _} = Enrollment.transfer(ctx.fm, e, ctx.other_cg)
    {:ok, e2} = Enrollment.fetch_owned_enrollment(ctx.head, e.id)
    assert_forbidden(Enrollment.transfer(ctx.fm, e2, ctx.cg))
  end

  test "only admins manage classes", ctx do
    attrs = %{label: "6ème Z", level: "6ème"}
    assert {:ok, _} = Enrollment.create_class_group(ctx.head, ctx.year, attrs)
    assert_forbidden(Enrollment.create_class_group(ctx.fm, ctx.year, %{attrs | label: "6ème Y"}))
    assert Enrollment.can_manage_classes?(ctx.head)
    refute Enrollment.can_manage_classes?(ctx.fm)
  end

  test "members read rosters; outsiders see none", ctx do
    {:ok, _} = Enrollment.enroll_new(ctx.head, ctx.cg, student())
    assert Enrollment.list_roster(ctx.teacher, ctx.cg) != []
    assert Enrollment.list_roster(ctx.outsider, ctx.cg) == []
  end

  test "a refused import row is a :forbidden conflict", ctx do
    rows = [%{full_name: "Imp #{System.unique_integer([:positive])}", sex: :m, matricule: nil}]

    assert %{created: 0, conflicts: [%{reason: :forbidden}]} =
             Enrollment.import_rows(ctx.teacher, ctx.cg, rows)
  end
end
