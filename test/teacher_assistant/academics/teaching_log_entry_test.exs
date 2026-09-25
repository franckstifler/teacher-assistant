defmodule TeacherAssistant.Academics.TeachingLogEntryTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, year: year, scope: scope} =
      TeacherFixtures.setup_complete_school_fixture()

    ctx =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "6ème",
        teacher: scope.current_user
      })

    {:ok, plan} = Curriculum.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, m1} = Curriculum.create_module(plan, %{title: "M1"})

    {:ok, entry} =
      Curriculum.add_progression_entry(m1, %{
        lesson_title: "L1",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    %{ws: ws, plan: plan, entry: entry}
  end

  test "log against a planned entry", %{ws: ws, plan: plan, entry: entry} do
    assert {:ok, log} =
             Curriculum.log_teaching(ws, %{
               date: ~D[2025-09-15],
               content_taught: "Intro",
               hours: Decimal.new("2"),
               status: :done,
               progression_entry_id: entry.id
             })

    assert log.status == :done
    assert [listed] = Curriculum.list_logs_for_plan!(plan.id, tenant: plan.workspace_id)
    assert listed.id == log.id
  end
end
