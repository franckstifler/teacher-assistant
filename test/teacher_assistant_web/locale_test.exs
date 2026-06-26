defmodule TeacherAssistantWeb.LocaleTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, _year} =
      TeacherAssistant.Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok
  end

  test "defaults to french and switches to english", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/teacher")
    assert html =~ "Tableau de bord"

    conn = get(conn, ~p"/locale/en")
    assert redirected_to(conn) == "/teacher"
    {:ok, _view, html} = live(conn, ~p"/teacher")
    assert html =~ "Teacher dashboard"
  end
end
