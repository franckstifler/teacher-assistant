defmodule TeacherAssistant.Authorization.AttendanceTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Attendance, Enrollment, Scope}

  setup do
    %{workspace: ws, scope: head} = setup_complete_school_fixture()
    %{teaching_context: tc, class_group: cg, scope: owner} = school_teacher_fixture(head)
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(head, cg, %{full_name: "Awa", sex: :f})
    [period | _] = Attendance.list_periods(head)
    other = member_scope_fixture(head, %{roles: [:teacher]})
    dm = member_scope_fixture(head, %{roles: [:discipline_master]})

    %{
      ws: ws,
      head: head,
      owner: owner,
      other: other,
      dm: dm,
      tc: tc,
      cg: cg,
      e: e,
      period: period
    }
  end

  defp roll(ctx, scope, tc),
    do:
      Attendance.record_period(scope, ctx.cg, ctx.period, tc, ~D[2025-09-15], [
        {ctx.e.id, :absent}
      ])

  test "the owner and the discipline master record; another teacher cannot", ctx do
    assert {:ok, _} = roll(ctx, ctx.owner, ctx.tc)
    assert {:ok, _} = roll(ctx, ctx.dm, ctx.tc)
    assert_forbidden(roll(ctx, ctx.other, ctx.tc))
  end

  test "an entry without a teaching context is conduct-only", ctx do
    assert {:ok, _} = roll(ctx, ctx.dm, nil)
    assert_forbidden(roll(ctx, ctx.owner, nil))
  end

  test "periods are admin-managed", ctx do
    assert Attendance.can_manage_periods?(ctx.head)
    refute Attendance.can_manage_periods?(ctx.dm)
    outsider = %Scope{current_user: user_fixture(), current_workspace: ctx.ws}
    assert Attendance.list_periods(outsider) == []
  end
end
