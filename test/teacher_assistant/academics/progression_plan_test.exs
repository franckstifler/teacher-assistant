defmodule TeacherAssistant.Academics.ProgressionPlanTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, head_user: head, year: year, scope: scope} =
      TeacherFixtures.setup_complete_school_fixture()

    ctx =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "6ème",
        teacher: head
      })

    %{ws: ws, year: year, scope: scope, ctx: ctx}
  end

  test "create and list a progression plan", %{ctx: ctx, scope: scope} do
    assert {:ok, plan} =
             Curriculum.create_progression_plan(scope, ctx, %{title: "Maths 6ème 2025-2026"})

    assert plan.status == :draft
    assert [listed] = Curriculum.list_progression_plans!(scope: scope)
    assert listed.id == plan.id
  end

  test "duplicate creates a new plan record", %{ctx: ctx, scope: scope} do
    {:ok, plan} = Curriculum.create_progression_plan(scope, ctx, %{title: "Original"})
    {:ok, copy} = Curriculum.duplicate_progression_plan(scope, plan, %{title: "Copy"})
    assert copy.id != plan.id
    assert copy.title == "Copy"
  end

  test "duplicate copies progression entries onto the new plan", %{ctx: ctx, scope: scope} do
    {:ok, plan} = Curriculum.create_progression_plan(scope, ctx, %{title: "Original"})

    {:ok, m1} = Curriculum.create_module(scope, plan, %{title: "M1"})
    {:ok, m2} = Curriculum.create_module(scope, plan, %{title: "M2"})

    {:ok, e1} =
      Curriculum.add_progression_entry(scope, m1, %{lesson_title: "Lesson 1"})

    {:ok, e2} =
      Curriculum.add_progression_entry(scope, m2, %{lesson_title: "Lesson 2"})

    {:ok, copy} = Curriculum.duplicate_progression_plan(scope, plan, %{title: "Copy"})

    original_entries = Curriculum.list_progression_entries!(plan.id, scope: scope)
    copied_entries = Curriculum.list_progression_entries!(copy.id, scope: scope)

    assert length(copied_entries) == 2

    original_ids = Enum.map(original_entries, & &1.id) |> MapSet.new()

    for ce <- copied_entries do
      refute MapSet.member?(original_ids, ce.id)
    end

    [c1, c2] =
      copied_entries
      |> Ash.load!(:progression_module, authorize?: false, tenant: copy.workspace_id)

    assert c1.progression_module.title == "M1"
    assert c1.lesson_title == e1.lesson_title
    assert c1.position == e1.position
    assert c2.progression_module.title == "M2"
    assert c2.lesson_title == e2.lesson_title
    assert c2.position == e2.position
  end

  test "duplicate copies module sequence_id and entry completed? flag", %{ctx: ctx, scope: scope} do
    {:ok, plan} = Curriculum.create_progression_plan(scope, ctx, %{title: "Original"})

    {:ok, ay} =
      Ash.get(TeacherAssistant.Academics.AcademicYear, plan.academic_year_id, scope: scope)

    :ok = Organization.build_default_calendar(scope, ay)
    [seq | _] = Organization.list_sequences(scope, ay)

    {:ok, m} = Curriculum.create_module(scope, plan, %{title: "M1"})
    {:ok, m} = Curriculum.assign_module_sequence(scope, m, seq.id)

    {:ok, e} =
      Curriculum.add_progression_entry(scope, m, %{lesson_title: "Lesson 1", entry_type: :lesson})

    {:ok, _e} = Curriculum.set_entry_completed(scope, e, true)

    {:ok, copy} = Curriculum.duplicate_progression_plan(scope, plan, %{title: "Copy"})

    [copied_module] =
      Curriculum.list_progression_modules!(copy.id, scope: scope)
      |> Enum.filter(&(!&1.default?))

    assert copied_module.sequence_id == seq.id
    assert [copied_entry] = copied_module.entries
    assert copied_entry.completed? == true
  end
end
