defmodule TeacherAssistant.Academics.ProgressionEntryTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{year: year, head_user: head, scope: scope} =
      TeacherFixtures.setup_complete_school_fixture()

    ctx =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "6ème",
        teacher: head
      })

    {:ok, plan} = Curriculum.create_progression_plan(ctx, %{title: "Plan"})
    %{plan: plan}
  end

  test "add entries get incrementing positions", %{plan: plan} do
    {:ok, m1} = Curriculum.create_module(plan, %{title: "M1"})

    {:ok, e1} =
      Curriculum.add_progression_entry(m1, %{
        lesson_title: "L1",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    {:ok, e2} =
      Curriculum.add_progression_entry(m1, %{
        lesson_title: "L2",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    assert e1.position == 1
    assert e2.position == 2
    assert length(Curriculum.list_progression_entries!(plan.id, tenant: plan.workspace_id)) == 2
  end

  test "entry defaults completed? to false and accepts it on update", %{plan: plan} do
    {:ok, m} = Curriculum.create_module(plan, %{title: "M1"})
    {:ok, e} = Curriculum.add_progression_entry(m, %{lesson_title: "L1", entry_type: :lesson})
    assert e.completed? == false

    {:ok, e} =
      e
      |> Ash.Changeset.for_update(:update, %{completed?: true})
      |> Ash.Changeset.set_tenant(e.workspace_id)
      |> Ash.update(authorize?: false)

    assert e.completed? == true
  end
end
