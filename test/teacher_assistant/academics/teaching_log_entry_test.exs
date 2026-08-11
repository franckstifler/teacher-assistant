defmodule TeacherAssistant.Academics.TeachingLogEntryTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()

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
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, m1} = Academics.create_module(plan, %{title: "M1"})

    {:ok, entry} =
      Academics.add_progression_entry(m1, %{
        lesson_title: "L1",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    %{ws: ws, plan: plan, entry: entry}
  end

  test "log against a planned entry", %{ws: ws, plan: plan, entry: entry} do
    assert {:ok, log} =
             Academics.log_teaching(ws, %{
               date: ~D[2025-09-15],
               content_taught: "Intro",
               hours: Decimal.new("2"),
               status: :done,
               progression_entry_id: entry.id
             })

    assert log.status == :done
    assert [listed] = Academics.list_logs_for_plan(plan)
    assert listed.id == log.id
  end
end
