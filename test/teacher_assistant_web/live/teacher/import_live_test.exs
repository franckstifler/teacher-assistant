defmodule TeacherAssistantWeb.Teacher.ImportLiveTest do
  use TeacherAssistantWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  defp seed_year_and_context(ws) do
    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Academics.build_default_calendar(year)

    {:ok, ctx} =
      Academics.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    %{year: year, ctx: ctx}
  end

  test "shows the upload form when a teaching context exists", %{conn: conn, workspace: ws} do
    seed_year_and_context(ws)
    {:ok, view, _html} = live(conn, ~p"/teacher/import")
    assert has_element?(view, "#import-upload-form")
    assert has_element?(view, "#import-context-select")
  end

  test "gates to setup when there is no teaching context", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/teacher/import")
    assert has_element?(view, "#import-context-gate")
    refute has_element?(view, "#import-upload-form")
  end
end
