defmodule TeacherAssistantWeb.Teacher.RosterLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
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

    %{ws: ws, year: year, ctx: ctx}
  end

  test "creates a class group then adds a student", %{conn: conn, ctx: ctx} do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/roster")

    view
    |> form("#roster-create-class-form", class_group: %{label: "3e M2", level: "3ème"})
    |> render_submit()

    view
    |> form("#student-form", student: %{full_name: "Awa Bello", sex: "f"})
    |> render_submit()

    assert render(view) =~ "Awa Bello"
  end

  test "unknown context redirects to setup", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/teacher/setup"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/roster")
  end
end
