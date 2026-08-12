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

  test "add entries into a module get per-module positions", %{plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, e1} = Academics.add_progression_entry(m, %{lesson_title: "L1", entry_type: :lesson})
    {:ok, e2} = Academics.add_progression_entry(m, %{lesson_title: "L2", entry_type: :lesson})
    assert e1.position == 1 and e2.position == 2
    assert e1.progression_module_id == m.id
  end

  test "delete_module reassigns entries to the default bucket and refuses on the bucket",
       %{plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})
    {:ok, _e} = Academics.add_progression_entry(m, %{lesson_title: "L1", entry_type: :lesson})
    {:ok, bucket} = Academics.ensure_default_module(plan)

    assert :ok = Academics.delete_module(m)
    [reloaded] = Academics.list_progression_modules(plan) |> Enum.filter(& &1.default?)
    assert reloaded.id == bucket.id
    assert length(reloaded.entries) == 1
    assert {:error, :default_bucket} = Academics.delete_module(bucket)
  end

  test "list_progression_modules returns modules ordered with ordered entries", %{plan: plan} do
    {:ok, m1} = Academics.create_module(plan, %{title: "M1"})
    {:ok, m2} = Academics.create_module(plan, %{title: "M2"})
    {:ok, _} = Academics.add_progression_entry(m1, %{lesson_title: "L1", entry_type: :lesson})
    mods = Academics.list_progression_modules(plan)
    assert Enum.map(mods, & &1.title) == ["M1", "M2"]
    assert [%{lesson_title: "L1"}] = hd(mods).entries
    assert m2.id in Enum.map(mods, & &1.id)
  end

  test "module accepts credit_hours via update", %{plan: plan} do
    {:ok, m} = Academics.create_module(plan, %{title: "M1"})

    {:ok, m} =
      m
      |> Ash.Changeset.for_update(:update, %{credit_hours: Decimal.new("11")})
      |> Ash.update(authorize?: false)

    assert Decimal.equal?(m.credit_hours, Decimal.new("11"))
  end
end
