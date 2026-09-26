defmodule TeacherAssistant.Authorization.OrganizationTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Organization, Scope}

  setup do
    %{workspace: ws, year: year, scope: head} = setup_complete_school_fixture()
    teacher = member_scope_fixture(head, %{roles: [:teacher]})
    vp = member_scope_fixture(head, %{roles: [:vice_principal]})
    outsider = %Scope{current_user: user_fixture(), current_workspace: ws}
    %{ws: ws, year: year, head: head, teacher: teacher, vp: vp, outsider: outsider}
  end

  defp year_attrs,
    do: %{name: "2030", start_date: ~D[2030-09-01], end_date: ~D[2031-07-01], active: false}

  test "admins create academic years; teachers, outsiders and no actor cannot", ctx do
    assert {:ok, _} = Organization.create_academic_year(ctx.vp, year_attrs())
    assert_forbidden(Organization.create_academic_year(ctx.teacher, year_attrs()))
    assert_forbidden(Organization.create_academic_year(ctx.outsider, year_attrs()))

    assert_forbidden(
      Organization.create_academic_year(%Scope{current_workspace: ctx.ws}, year_attrs())
    )
  end

  test "members read the calendar; outsiders see nothing", ctx do
    assert Organization.list_sequences(ctx.teacher, ctx.year) != []
    assert Organization.list_sequences(ctx.outsider, ctx.year) == []
    assert Organization.current_academic_year(ctx.outsider) == nil
  end

  test "only the head renames the school", ctx do
    assert {:ok, _} = Organization.rename_school(ctx.ws, "Nouveau nom", scope: ctx.head)
    assert_forbidden(Organization.rename_school(ctx.ws, "Autre", scope: ctx.vp))
  end

  test "a member reads their workspace; an outsider cannot; the operator can", ctx do
    assert {:ok, _} = Organization.get_workspace(ctx.ws.id, scope: ctx.teacher)
    assert {:error, _} = Organization.get_workspace(ctx.ws.id, scope: ctx.outsider)
    operator = admin_user_fixture()
    assert {:ok, _} = Organization.get_workspace(ctx.ws.id, actor: operator)
  end

  test "any signed-in user can create a school; nobody signed-out can" do
    assert {:ok, _} =
             Organization.create_school(%Scope{current_user: user_fixture()}, %{name: "Lycée X"})

    assert_forbidden(Organization.create_school(%Scope{}, %{name: "Lycée Y"}))
  end

  test "can_* answer the role gates", ctx do
    assert Organization.can_manage_calendar?(ctx.vp)
    refute Organization.can_manage_calendar?(ctx.teacher)
    assert Organization.can_rename_school?(ctx.head)
    refute Organization.can_rename_school?(ctx.vp)
  end
end
