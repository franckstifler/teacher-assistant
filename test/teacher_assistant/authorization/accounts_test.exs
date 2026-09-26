defmodule TeacherAssistant.Authorization.AccountsTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Accounts, Scope}

  setup do
    %{workspace: ws, scope: head} = setup_complete_school_fixture()
    vp = member_scope_fixture(head, %{roles: [:vice_principal]})
    teacher = member_scope_fixture(head, %{roles: [:teacher]})
    %{ws: ws, head: head, vp: vp, teacher: teacher}
  end

  test "only the head invites and manages staff", ctx do
    assert {:ok, _} =
             Accounts.invite_member(ctx.head, %{email: "a@example.com", roles: [:teacher]})

    assert_forbidden(Accounts.invite_member(ctx.vp, %{email: "b@example.com", roles: [:teacher]}))
    {:ok, m} = Accounts.fetch_school_membership(ctx.head, ctx.teacher.current_user)
    assert_forbidden(Accounts.update_member_roles(ctx.vp, m, [:bursar]))
    assert Accounts.can_manage_staff?(ctx.head)
    refute Accounts.can_manage_staff?(ctx.vp)
  end

  test "the invitee accepts by email match; anyone else is refused", ctx do
    invitee = user_fixture()

    {:ok, inv} =
      Accounts.invite_member(ctx.head, %{email: to_string(invitee.email), roles: [:bursar]})

    assert {:error, :email_mismatch} =
             Accounts.accept_invitation(%Scope{current_user: user_fixture()}, inv.token)

    assert {:ok, ws} = Accounts.accept_invitation(%Scope{current_user: invitee}, inv.token)
    assert ws.id == ctx.ws.id

    assert {:ok, %{roles: [:bursar]}} =
             Accounts.fetch_school_membership(school_scope(invitee, ws), invitee)

    assert {:error, :invalid} =
             Accounts.accept_invitation(%Scope{current_user: invitee}, inv.token)
  end

  test "a revoked member is refused on their next call", ctx do
    {:ok, m} = Accounts.fetch_school_membership(ctx.head, ctx.vp.current_user)
    {:ok, _} = Accounts.deactivate_member(ctx.head, m)

    assert_forbidden(
      TeacherAssistant.Organization.create_academic_year(ctx.vp, %{
        name: "2031",
        start_date: ~D[2031-09-01],
        end_date: ~D[2032-07-01],
        active: false
      })
    )
  end

  test "school profile: admins edit, members read, the operator verifies", ctx do
    {:ok, profile} = Accounts.fetch_school_profile(ctx.teacher)
    assert Accounts.can_edit_profile?(ctx.vp, profile)
    refute Accounts.can_edit_profile?(ctx.teacher, profile)
    assert_forbidden(Accounts.verify_school(profile, ctx.head.current_user.id, scope: ctx.head))
    operator = admin_user_fixture()
    assert {:ok, _} = Accounts.verify_school(profile, operator.id, actor: operator)
  end

  test "users are visible to themselves, co-members and the operator only", ctx do
    outsider = user_fixture()

    assert {:ok, _} =
             Ash.get(Accounts.User, ctx.teacher.current_user.id, actor: ctx.head.current_user)

    assert {:error, _} = Ash.get(Accounts.User, ctx.teacher.current_user.id, actor: outsider)

    assert {:ok, _} =
             Ash.get(Accounts.User, ctx.teacher.current_user.id, actor: admin_user_fixture())
  end
end
