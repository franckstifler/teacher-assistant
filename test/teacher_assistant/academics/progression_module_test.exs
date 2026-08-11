defmodule TeacherAssistant.Academics.ProgressionModuleTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.ProgressionModule
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

  test "creates a module belonging to a plan", %{plan: plan} do
    {:ok, m} =
      ProgressionModule
      |> Ash.Changeset.for_create(:create, %{
        title: "M1",
        position: 1,
        progression_plan_id: plan.id
      })
      |> Ash.create(authorize?: false)

    assert m.title == "M1"
    assert m.position == 1
    assert m.default? == false
  end
end
