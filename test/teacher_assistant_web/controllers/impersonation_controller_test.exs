defmodule TeacherAssistantWeb.ImpersonationControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  require Ash.Query
  import Ecto.Query, only: [from: 2]

  alias TeacherAssistant.Accounts.AuditEvent
  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistantWeb.Impersonation

  setup %{conn: conn} do
    %{workspace: ws, head_user: head, scope: head_scope} =
      TeacherFixtures.setup_complete_school_fixture()

    teacher = TeacherFixtures.user_fixture()
    TeacherFixtures.membership_fixture(head_scope, %{user: teacher, roles: [:teacher]})
    op = TeacherFixtures.admin_user_fixture()

    %{conn: log_in_user(conn, op), ws: ws, head: head, teacher: teacher, op: op}
  end

  defp start(conn, user, ws),
    do: post(conn, ~p"/impersonation?#{%{user_id: user.id, workspace_id: ws.id}}")

  defp set_user(user, fields) do
    {1, _} =
      TeacherAssistant.Repo.update_all(
        from(u in "users", where: u.id == type(^user.id, :binary_id)),
        set: fields
      )
  end

  defp journal(action) do
    AuditEvent
    |> Ash.Query.filter(action == ^action)
    |> Ash.read!(authorize?: false)
  end

  test "the operator acts as the head, with the strip, then comes back", ctx do
    conn = start(ctx.conn, ctx.head, ctx.ws)
    assert redirected_to(conn) == ~p"/school"

    assert [%{target_user_id: target, workspace_id: ws_id, actor_user_id: actor}] =
             journal(:impersonation_started)

    assert {target, ws_id, actor} == {ctx.head.id, ctx.ws.id, ctx.op.id}

    {:ok, view, _html} = live(recycle(conn), ~p"/school/members")

    assert has_element?(
             view,
             "#impersonation-bar",
             TeacherAssistant.Accounts.User.display_name(ctx.head)
           )

    conn = delete(recycle(conn), ~p"/impersonation")
    assert redirected_to(conn) == ~p"/admin/schools/#{ctx.ws.id}"
    assert [%{details: %{"reason" => "stopped"}}] = journal(:impersonation_ended)
    refute get_session(conn, :impersonation)

    {:ok, view, _html} = live(recycle(conn), ~p"/admin")
    refute has_element?(view, "#impersonation-bar")
  end

  test "acting as a teacher builds the teacher's scope", ctx do
    conn = start(ctx.conn, ctx.teacher, ctx.ws)
    conn = get(recycle(conn), ~p"/school/logo")
    assert conn.assigns.current_scope.current_user.id == ctx.teacher.id
    assert conn.assigns.current_scope.current_roles == [:teacher]
    assert conn.assigns.current_scope.impersonation.operator.id == ctx.op.id
  end

  test "another operator, a stranger to the school or a non-operator is refused", ctx do
    other_op = TeacherFixtures.admin_user_fixture()
    stranger = TeacherFixtures.user_fixture()

    for user <- [other_op, stranger] do
      conn = start(ctx.conn, user, ctx.ws)
      assert redirected_to(conn) == ~p"/admin/schools/#{ctx.ws.id}"
      refute get_session(conn, :impersonation)
    end

    conn = build_conn() |> log_in_user(ctx.head) |> start(ctx.teacher, ctx.ws)
    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, :impersonation)
    assert journal(:impersonation_started) == []
  end

  test "the session switch takes no GET", %{conn: conn} do
    assert conn |> get("/impersonation") |> response(404)
  end

  defp acting(ctx, user, started_at) do
    ctx.conn
    |> Plug.Conn.put_session(
      :impersonation,
      Impersonation.session_value(user.id, ctx.ws.id, nil, started_at)
    )
    |> Plug.Conn.put_session(:workspace_id, ctx.ws.id)
  end

  test "after an hour the next request ends it and returns to the console", ctx do
    conn = ctx |> acting(ctx.head, System.os_time(:second) - 3601) |> get(~p"/school")
    assert redirected_to(conn) == ~p"/admin"
    refute get_session(conn, :impersonation)
    assert [%{details: %{"reason" => "expired"}}] = journal(:impersonation_ended)
  end

  test "an open page leaves when the hour is over", ctx do
    {:ok, view, _html} =
      ctx |> acting(ctx.head, System.os_time(:second)) |> live(~p"/school/members")

    send(view.pid, :impersonation_over)
    assert_redirect(view, ~p"/admin")
  end

  test "an operator who loses the role is no longer acting", ctx do
    conn = acting(ctx, ctx.head, System.os_time(:second))

    set_user(ctx.op, role: "teacher")

    conn = get(conn, ~p"/school")
    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, :impersonation)
  end

  test "the member's password page is refused, and a temporary password does not block", ctx do
    set_user(ctx.teacher, must_change_password: true)

    conn = acting(ctx, ctx.teacher, System.os_time(:second))

    assert {:error, {:redirect, %{to: "/school"}}} = live(conn, ~p"/account/password")
    refute match?({:error, {:redirect, %{to: "/account/password"}}}, live(conn, ~p"/school"))
  end

  test "signing out ends it in the journal", ctx do
    conn = ctx |> acting(ctx.head, System.os_time(:second)) |> delete(~p"/sign-out")
    assert redirected_to(conn)
    assert [%{details: %{"reason" => "signed_out"}}] = journal(:impersonation_ended)
  end
end
