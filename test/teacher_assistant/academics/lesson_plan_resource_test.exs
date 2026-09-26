defmodule TeacherAssistant.Academics.LessonPlanResourceTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.{LessonPlan, LessonStep}
  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Curriculum

  setup do
    %{head_user: head, year: year, scope: scope} =
      TeacherFixtures.setup_complete_school_fixture()

    ctx =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "6ème",
        teacher: head
      })

    {:ok, plan} = Curriculum.create_progression_plan(scope, ctx, %{title: "Plan"})

    {:ok, m1} = Curriculum.create_module(scope, plan, %{title: "M1"})

    {:ok, entry} =
      Curriculum.add_progression_entry(scope, m1, %{
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    %{scope: scope, entry: entry}
  end

  test "a lesson plan persists and links to its entry", %{entry: entry, scope: scope} do
    {:ok, lp} =
      LessonPlan
      |> Ash.Changeset.for_create(:create, %{
        progression_entry_id: entry.id,
        titre: "Les entiers"
      })
      |> Ash.create(scope: scope)

    assert lp.progression_entry_id == entry.id
    assert lp.duration_minutes == 55
  end

  test "the entry↔plan link is 1:1 (unique)", %{entry: entry, scope: scope} do
    {:ok, _} =
      LessonPlan
      |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id})
      |> Ash.create(scope: scope)

    assert {:error, _} =
             LessonPlan
             |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id})
             |> Ash.create(scope: scope)
  end

  test "steps persist against a lesson plan", %{entry: entry, scope: scope} do
    {:ok, lp} =
      LessonPlan
      |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id})
      |> Ash.create(scope: scope)

    {:ok, step} =
      LessonStep
      |> Ash.Changeset.for_create(:create, %{
        lesson_plan_id: lp.id,
        position: 1,
        etape: "Découverte"
      })
      |> Ash.create(scope: scope)

    assert step.position == 1
    assert step.etape == "Découverte"
  end
end
