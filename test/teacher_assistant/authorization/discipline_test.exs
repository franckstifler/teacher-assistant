defmodule TeacherAssistant.Authorization.DisciplineTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Discipline, Enrollment, Organization, Scope}

  setup do
    %{workspace: ws, year: year, scope: head} = setup_complete_school_fixture()
    [cg | _] = Enrollment.list_class_groups(head, year)
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(head, cg, %{full_name: "Awa", sex: :f})
    fm = member_scope_fixture(head, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(head, cg, fm.current_user.id)
    dm = member_scope_fixture(head, %{roles: [:discipline_master]})
    teacher = member_scope_fixture(head, %{roles: [:teacher]})
    [seq | _] = Organization.list_sequences(head, year)
    %{ws: ws, head: head, fm: fm, dm: dm, teacher: teacher, cg: cg, e: e, seq: seq}
  end

  defp sanction(ctx), do: %{type: :avertissement, date: ctx.seq.start_date}

  test "the conduct axis writes; form masters and teachers cannot", ctx do
    assert {:ok, _} = Discipline.add_sanction(ctx.dm, ctx.e, sanction(ctx))
    assert_forbidden(Discipline.add_sanction(ctx.fm, ctx.e, sanction(ctx)))
    assert_forbidden(Discipline.add_sanction(ctx.teacher, ctx.e, sanction(ctx)))
  end

  test "sanctions are readable by the conduct axis and the class's form master only", ctx do
    {:ok, _} = Discipline.add_sanction(ctx.dm, ctx.e, sanction(ctx))
    period = {:sequence, ctx.seq}
    assert Discipline.list_sanctions(ctx.dm, ctx.e, period) != []
    assert Discipline.list_sanctions(ctx.fm, ctx.e, period) != []
    assert Discipline.list_sanctions(ctx.teacher, ctx.e, period) == []
    outsider = %Scope{current_user: user_fixture(), current_workspace: ctx.ws}
    assert Discipline.list_sanctions(outsider, ctx.e, period) == []
  end

  test "can_manage_conduct? follows the axis", ctx do
    assert Discipline.can_manage_conduct?(ctx.dm)
    refute Discipline.can_manage_conduct?(ctx.fm)
  end
end
