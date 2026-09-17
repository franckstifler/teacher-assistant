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

    {:ok, m1} = Academics.create_module(plan, %{title: "M1"})
    {:ok, m2} = Academics.create_module(plan, %{title: "M2"})

    {:ok, e1} =
      Academics.add_progression_entry(m1, %{lesson_title: "Lesson 1"})

    {:ok, e2} =
      Academics.add_progression_entry(m2, %{lesson_title: "Lesson 2"})

    {:ok, copy} = Academics.duplicate_progression_plan(plan, %{title: "Copy"})

    original_entries = Academics.list_progression_entries(plan)
    copied_entries = Academics.list_progression_entries(copy)

    assert length(copied_entries) == 2

    original_ids = Enum.map(original_entries, & &1.id) |> MapSet.new()

    for ce <- copied_entries do
      refute MapSet.member?(original_ids, ce.id)
    end

    [c1, c2] = copied_entries |> Ash.load!(:progression_module, authorize?: false)
    assert c1.progression_module.title == "M1"
    assert c1.lesson_title == e1.lesson_title
    assert c1.position == e1.position
    assert c2.progression_module.title == "M2"
    assert c2.lesson_title == e2.lesson_title
    assert c2.position == e2.position
  end

  test "duplicate copies module sequence_id and entry completed? flag", %{ctx: ctx} do
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Original"})

    {:ok, ay} =
      Ash.get(TeacherAssistant.Academics.AcademicYear, plan.academic_year_id, authorize?: false)

    :ok = Academics.build_default_calendar(ay)
    [seq | _] = Academics.list_sequences(ay)

    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, m} = Academics.assign_module_sequence(m, seq.id)

    {:ok, e} =
      Academics.add_progression_entry(m, %{lesson_title: "Lesson 1", entry_type: :lesson})

    {:ok, _e} = Academics.set_entry_completed(e, true)

    {:ok, copy} = Academics.duplicate_progression_plan(plan, %{title: "Copy"})

    [copied_module] = Academics.list_progression_modules(copy) |> Enum.filter(&(!&1.default?))
    assert copied_module.sequence_id == seq.id
    assert [copied_entry] = copied_module.entries
    assert copied_entry.completed? == true
  end
end
