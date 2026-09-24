defmodule TeacherAssistant.Academics.LessonPlanResourceTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.{LessonPlan, LessonStep}
  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Curriculum

  setup do
    %{workspace: ws, head_user: head, year: year} =
      TeacherFixtures.setup_complete_school_fixture()

    ctx =
      TeacherFixtures.assigned_context_fixture(ws, year, %{
        subject: "Maths",
        level: "6ème",
        teacher: head
      })

    {:ok, plan} = Curriculum.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, m1} = Curriculum.create_module(plan, %{title: "M1"})

    {:ok, entry} =
      Curriculum.add_progression_entry(m1, %{
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    %{ws: ws, entry: entry}
  end

  test "a lesson plan persists and links to its entry", %{entry: entry} do
    {:ok, lp} =
      LessonPlan
      |> Ash.Changeset.for_create(:create, %{
        progression_entry_id: entry.id,
        titre: "Les entiers"
      })
      |> Ash.Changeset.set_tenant(entry.workspace_id)
      |> Ash.create(authorize?: false)

    assert lp.progression_entry_id == entry.id
    assert lp.duration_minutes == 55
  end

  test "the entry↔plan link is 1:1 (unique)", %{entry: entry} do
    {:ok, _} =
      LessonPlan
      |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id})
      |> Ash.Changeset.set_tenant(entry.workspace_id)
      |> Ash.create(authorize?: false)

    assert {:error, _} =
             LessonPlan
             |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id})
             |> Ash.Changeset.set_tenant(entry.workspace_id)
             |> Ash.create(authorize?: false)
  end

  test "steps persist against a lesson plan", %{entry: entry} do
    {:ok, lp} =
      LessonPlan
      |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id})
      |> Ash.Changeset.set_tenant(entry.workspace_id)
      |> Ash.create(authorize?: false)

    {:ok, step} =
      LessonStep
      |> Ash.Changeset.for_create(:create, %{
        lesson_plan_id: lp.id,
        position: 1,
        etape: "Découverte"
      })
      |> Ash.Changeset.set_tenant(lp.workspace_id)
      |> Ash.create(authorize?: false)

    assert step.position == 1
    assert step.etape == "Découverte"
  end
end
