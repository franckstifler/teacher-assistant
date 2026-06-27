defmodule TeacherAssistant.Academics.ProgressionPlanTest do
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

  test "duplicate copies progression entries onto the new plan", %{ctx: ctx} do
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Original"})

    {:ok, e1} =
      Academics.add_progression_entry(plan, %{module: "M1", lesson_title: "Lesson 1", position: 1})

    {:ok, e2} =
      Academics.add_progression_entry(plan, %{module: "M2", lesson_title: "Lesson 2", position: 2})

    {:ok, copy} = Academics.duplicate_progression_plan(plan, %{title: "Copy"})

    original_entries = Academics.list_progression_entries(plan)
    copied_entries = Academics.list_progression_entries(copy)

    assert length(copied_entries) == 2

    original_ids = Enum.map(original_entries, & &1.id) |> MapSet.new()

    for ce <- copied_entries do
      refute MapSet.member?(original_ids, ce.id)
    end

    [c1, c2] = copied_entries
    assert c1.module == e1.module
    assert c1.lesson_title == e1.lesson_title
    assert c1.position == e1.position
    assert c2.module == e2.module
    assert c2.lesson_title == e2.lesson_title
    assert c2.position == e2.position
  end
end
