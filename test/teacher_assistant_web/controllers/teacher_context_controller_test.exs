defmodule TeacherAssistantWeb.TeacherContextControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.TeacherFixtures
  setup :register_and_log_in_user

  setup %{workspace: school, year: year, actor: head, scope: scope} do
    ctx =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "3ème",
        teacher: head
      })

    %{ws: school, ctx: ctx}
  end

  test "selecting a valid class stores it and honors return_to", %{conn: conn, ctx: ctx} do
    conn =
      get(
        conn,
        "/teacher/select-context/#{ctx.id}?return_to=/teacher/contexts/#{ctx.id}/roster"
      )

    assert redirected_to(conn) == "/teacher/contexts/#{ctx.id}/roster"
    assert get_session(conn, :context_id) == ctx.id
  end

  test "rewrites the id segment of a per-class return_to", %{conn: conn, ctx: ctx} do
    other = Ecto.UUID.generate()

    conn =
      get(conn, "/teacher/select-context/#{ctx.id}?return_to=/teacher/contexts/#{other}/marks")

    assert redirected_to(conn) == "/teacher/contexts/#{ctx.id}/marks"
  end

  test "rejects a foreign id without writing the session", %{conn: conn} do
    conn = get(conn, ~p"/teacher/select-context/#{Ecto.UUID.generate()}?return_to=/teacher/log")
    assert redirected_to(conn) == "/school"
    assert get_session(conn, :context_id) == nil
  end

  test "ignores a non-local return_to", %{conn: conn, ctx: ctx} do
    conn = get(conn, ~p"/teacher/select-context/#{ctx.id}?return_to=https://evil.example/x")
    assert redirected_to(conn) == "/school"
  end

  test "a paused personal return_to falls back to /school", %{conn: conn, ctx: ctx} do
    conn = get(conn, ~p"/teacher/select-context/#{ctx.id}?return_to=/teacher/log")
    assert redirected_to(conn) == "/school"
  end

  test "selecting a context while signed out redirects to sign-in", %{conn: _conn} do
    conn =
      build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> get(~p"/teacher/select-context/#{Ecto.UUID.generate()}")

    assert redirected_to(conn) == ~p"/sign-in"
  end
end
