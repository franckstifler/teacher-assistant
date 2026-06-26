defmodule TeacherAssistantWeb.Teacher.SetupLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  test "completing setup creates a year, calendar and teaching context", %{conn: conn, workspace: ws} do
    {:ok, view, _html} = live(conn, ~p"/teacher/setup")

    view
    |> form("#setup-form", setup: %{
      name: "2025-2026", start_date: "2025-09-08", end_date: "2026-07-31",
      subsystem: "francophone", subject: "Mathématiques", level: "6ème", weekly_hours: "4"
    })
    |> render_submit()

    year = Academics.current_academic_year(ws)
    assert year.name == "2025-2026"
    assert length(Academics.list_sequences(year)) == 6
    assert [_ctx] = Academics.list_teaching_contexts(ws, year)
  end
end
