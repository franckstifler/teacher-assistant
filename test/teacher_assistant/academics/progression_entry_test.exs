defmodule TeacherAssistant.Academics.ProgressionEntryTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()
    {:ok, year} = Academics.create_academic_year(ws, %{name: "2025-2026", start_date: ~D[2025-09-08], end_date: ~D[2026-07-31], active: true})
    {:ok, ctx} = Academics.create_teaching_context(ws, year, %{subject: "Maths", level: "6ème", subsystem: :francophone, weekly_hours: 4})
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})
    %{plan: plan}
  end

  test "add entries get incrementing positions", %{plan: plan} do
    {:ok, e1} = Academics.add_progression_entry(plan, %{module: "M1", lesson_title: "L1", planned_hours: Decimal.new("2"), entry_type: :lesson})
    {:ok, e2} = Academics.add_progression_entry(plan, %{module: "M1", lesson_title: "L2", planned_hours: Decimal.new("2"), entry_type: :lesson})
    assert e1.position == 1
    assert e2.position == 2
    assert length(Academics.list_progression_entries(plan)) == 2
  end
end
