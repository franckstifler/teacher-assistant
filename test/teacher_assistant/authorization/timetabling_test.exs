defmodule TeacherAssistant.Authorization.TimetablingTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Attendance, Scope, Timetabling}

  setup do
    %{workspace: ws, scope: head} = setup_complete_school_fixture()
    %{teaching_context: tc, class_group: cg, scope: owner} = school_teacher_fixture(head)
    [period | _] = Attendance.list_periods(head)
    %{ws: ws, head: head, owner: owner, tc: tc, cg: cg, period: period}
  end

  defp attrs(ctx), do: %{day: :monday, period_id: ctx.period.id, teaching_context_id: ctx.tc.id}

  test "admins place slots; teachers cannot", ctx do
    assert_forbidden(Timetabling.place_slot(ctx.owner, ctx.cg, attrs(ctx)))
    assert {:ok, _} = Timetabling.place_slot(ctx.head, ctx.cg, attrs(ctx))
    assert Timetabling.can_edit_timetable?(ctx.head)
    refute Timetabling.can_edit_timetable?(ctx.owner)
  end

  test "members read the timetable; outsiders see an empty one", ctx do
    {:ok, _} = Timetabling.place_slot(ctx.head, ctx.cg, attrs(ctx))
    outsider = %Scope{current_user: user_fixture(), current_workspace: ctx.ws}
    assert Timetabling.list_for_class!(ctx.cg.id, scope: ctx.owner) != []
    assert Timetabling.list_for_class!(ctx.cg.id, scope: outsider) == []
  end
end
