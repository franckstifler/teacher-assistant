defmodule TeacherAssistantWeb.Teacher.ShellTest do
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

  test "shell shows the class switcher with the active class and per-class tabs", %{
    conn: conn,
    ctx: ctx
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher")
    assert has_element?(view, "#class-switcher", "Maths")
    assert has_element?(view, "#class-switcher-item-#{ctx.id}")
    assert has_element?(view, "#per-class-nav")
    # per-class links point at the active context
    assert has_element?(view, "#per-class-nav a[href='/teacher/contexts/#{ctx.id}/marks']")
  end

  test "switcher items link through select-context carrying the current path", %{
    conn: conn,
    ctx: ctx
  } do
    {:ok, view, _html} = live(conn, ~p"/teacher")

    assert has_element?(
             view,
             "#class-switcher-item-#{ctx.id} a[href*='/teacher/select-context/#{ctx.id}']"
           )
  end

  test "with no class, the switcher invites setup and hides per-class tabs", %{
    conn: conn,
    ws: ws
  } do
    # a workspace whose only class is removed → resolve returns nil
    for c <- Academics.list_teaching_contexts(ws, Academics.current_academic_year(ws)),
        do: Ash.destroy!(c, authorize?: false)

    {:ok, view, _html} = live(conn, ~p"/teacher")

    assert has_element?(view, "#class-switcher", "Set up a class") or
             has_element?(view, "#class-switcher", "Configurer")

    refute has_element?(view, "#per-class-nav")
  end
end
