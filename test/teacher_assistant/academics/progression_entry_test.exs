defmodule TeacherAssistant.Academics.ProgressionEntryTest do
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
    %{plan: plan}
  end

  test "add entries get incrementing positions", %{plan: plan} do
    {:ok, m1} = Academics.create_module(plan, %{title: "M1"})

    {:ok, e1} =
      Academics.add_progression_entry(m1, %{
        lesson_title: "L1",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    {:ok, e2} =
      Academics.add_progression_entry(m1, %{
        lesson_title: "L2",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    assert e1.position == 1
    assert e2.position == 2
    assert length(Academics.list_progression_entries(plan)) == 2
  end

  test "entry defaults completed? to false and accepts it on update", %{plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, e} = Academics.add_progression_entry(m, %{lesson_title: "L1", entry_type: :lesson})
    assert e.completed? == false
    {:ok, e} = e |> Ash.Changeset.for_update(:update, %{completed?: true}) |> Ash.update(authorize?: false)
    assert e.completed? == true
  end
end
