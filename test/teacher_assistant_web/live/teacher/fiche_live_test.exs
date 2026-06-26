defmodule TeacherAssistantWeb.Teacher.FicheLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  setup :register_and_log_in_user

  setup %{workspace: ws} do
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    :ok = Academics.build_default_calendar(year)
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Maths 6ème"})
    %{plan: plan}
  end

  test "add an entry to the plan", %{conn: conn, plan: plan} do
    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}")

    view
    |> form("#add-entry-form", entry: %{module: "Module 1", lesson_title: "Les nombres", planned_hours: "2", entry_type: "lesson"})
    |> render_submit()

    assert has_element?(view, "#fiche-entries")
    assert render(view) =~ "Les nombres"
    assert length(Academics.list_progression_entries(plan)) == 1
  end
end
