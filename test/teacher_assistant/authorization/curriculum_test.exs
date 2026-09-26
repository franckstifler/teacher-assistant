defmodule TeacherAssistant.Authorization.CurriculumTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Curriculum, Scope}

  setup do
    %{workspace: ws, year: year, scope: head} = setup_complete_school_fixture()
    %{teaching_context: tc, scope: owner} = school_teacher_fixture(head)
    other = member_scope_fixture(head, %{roles: [:teacher]})
    outsider = %Scope{current_user: user_fixture(), current_workspace: ws}
    %{ws: ws, year: year, head: head, owner: owner, other: other, outsider: outsider, tc: tc}
  end

  test "the owner and admins write a progression plan; another teacher cannot", ctx do
    assert {:ok, plan} = Curriculum.create_progression_plan(ctx.owner, ctx.tc, %{title: "Plan"})
    assert {:ok, _} = Curriculum.create_module(ctx.head, plan, %{title: "Module A"})
    assert_forbidden(Curriculum.create_module(ctx.other, plan, %{title: "Module B"}))
    assert_forbidden(Curriculum.create_progression_plan(ctx.other, ctx.tc, %{title: "Plan 2"}))
  end

  test "only admins manage subjects and assignments", ctx do
    assert {:ok, _} = Curriculum.create_subject(ctx.head, %{name: "Latin", position: 90})
    assert_forbidden(Curriculum.create_subject(ctx.owner, %{name: "Grec", position: 91}))
    assert_forbidden(Curriculum.remove_assignment(ctx.owner, ctx.tc))
    assert Curriculum.can_manage_subjects?(ctx.head)
    refute Curriculum.can_manage_subjects?(ctx.owner)
  end

  test "members read; outsiders and no actor see nothing", ctx do
    assert Curriculum.list_subjects(ctx.other) != []
    assert Curriculum.list_subjects(ctx.outsider) == []
    assert Curriculum.list_subjects(%Scope{current_workspace: ctx.ws}) == []
  end

  # combine_course/2 validates count/teacher/subject before running the action,
  # so the refusal is exercised with two valid contexts of the same teacher.
  test "combining courses is admin-only", ctx do
    [_first, second_cg | _] = TeacherAssistant.Enrollment.list_class_groups(ctx.head, ctx.year)

    %{teaching_context: tc2} =
      school_teacher_fixture(ctx.head, %{teacher: ctx.owner.current_user, class_group: second_cg})

    assert_forbidden(Curriculum.combine_course(ctx.owner, [ctx.tc, tc2]))
    assert {:ok, _course} = Curriculum.combine_course(ctx.head, [ctx.tc, tc2])
  end
end
