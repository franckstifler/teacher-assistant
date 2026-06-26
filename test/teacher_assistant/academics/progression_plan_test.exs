defmodule TeacherAssistant.Academics.ProgressionPlanTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    %{ws: ws, year: year, ctx: ctx}
  end

  test "create and list a progression plan", %{ws: ws, ctx: ctx} do
    assert {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Maths 6ème 2025-2026"})
    assert plan.status == :draft
    assert [listed] = Academics.list_progression_plans(ws)
    assert listed.id == plan.id
  end

  test "duplicate creates a new plan record", %{ctx: ctx} do
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Original"})
    {:ok, copy} = Academics.duplicate_progression_plan(plan, %{title: "Copy"})
    assert copy.id != plan.id
    assert copy.title == "Copy"
  end
end
