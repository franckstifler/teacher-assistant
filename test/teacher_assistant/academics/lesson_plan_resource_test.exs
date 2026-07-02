defmodule TeacherAssistant.Academics.LessonPlanResourceTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{LessonPlan, LessonStep}
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    ws = Academics.ensure_personal_workspace!(user)

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

    {:ok, entry} =
      Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    %{ws: ws, entry: entry}
  end

  test "a lesson plan persists and links to its entry", %{entry: entry} do
    {:ok, lp} =
      LessonPlan
      |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id, titre: "Les entiers"})
      |> Ash.create(authorize?: false)

    assert lp.progression_entry_id == entry.id
    assert lp.duration_minutes == 55
  end

  test "the entry↔plan link is 1:1 (unique)", %{entry: entry} do
    {:ok, _} =
      LessonPlan
      |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id})
      |> Ash.create(authorize?: false)

    assert {:error, _} =
             LessonPlan
             |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id})
             |> Ash.create(authorize?: false)
  end

  test "steps persist against a lesson plan", %{entry: entry} do
    {:ok, lp} =
      LessonPlan
      |> Ash.Changeset.for_create(:create, %{progression_entry_id: entry.id})
      |> Ash.create(authorize?: false)

    {:ok, step} =
      LessonStep
      |> Ash.Changeset.for_create(:create, %{
        lesson_plan_id: lp.id,
        position: 1,
        etape: "Découverte"
      })
      |> Ash.create(authorize?: false)

    assert step.position == 1
    assert step.etape == "Découverte"
  end
end
