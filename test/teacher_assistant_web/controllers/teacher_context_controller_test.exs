defmodule TeacherAssistantWeb.TeacherContextControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    %{ws: ws, ctx: ctx}
  end

  test "selecting a valid class stores it and honors return_to", %{conn: conn, ctx: ctx} do
    conn = get(conn, ~p"/teacher/select-context/#{ctx.id}?return_to=/teacher/log")
    assert redirected_to(conn) == "/teacher/log"
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
    assert redirected_to(conn) == "/teacher/setup"
    assert get_session(conn, :context_id) == nil
  end

  test "ignores a non-local return_to", %{conn: conn, ctx: ctx} do
    conn = get(conn, ~p"/teacher/select-context/#{ctx.id}?return_to=https://evil.example/x")
    assert redirected_to(conn) == "/teacher"
  end
end
