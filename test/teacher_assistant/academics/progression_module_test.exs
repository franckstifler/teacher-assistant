defmodule TeacherAssistant.Academics.ProgressionModuleTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Academics.ProgressionModule
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

    {:ok, plan} = Curriculum.create_progression_plan(scope, ctx, %{title: "Plan"})
    %{ws: ws, scope: scope, plan: plan}
  end

  defp seed_sequence(plan) do
    {:ok, ay} =
      Ash.get(TeacherAssistant.Academics.AcademicYear, plan.academic_year_id,
        authorize?: false,
        tenant: plan.workspace_id
      )

    :ok = Organization.build_default_calendar(ay)
    [seq | _] = Organization.list_sequences(ay)
    seq
  end

  test "creates a module belonging to a plan", %{plan: plan} do
    {:ok, m} =
      ProgressionModule
      |> Ash.Changeset.for_create(:create, %{
        title: "M1",
        position: 1,
        progression_plan_id: plan.id
      })
      |> Ash.Changeset.set_tenant(plan.workspace_id)
      |> Ash.create(authorize?: false)

    assert m.title == "M1"
    assert m.position == 1
    assert m.default? == false
  end

  test "add entries into a module get per-module positions", %{plan: plan, scope: scope} do
    {:ok, m} = Curriculum.create_module(scope, plan, %{title: "M1"})

    {:ok, e1} =
      Curriculum.add_progression_entry(scope, m, %{lesson_title: "L1", entry_type: :lesson})

    {:ok, e2} =
      Curriculum.add_progression_entry(scope, m, %{lesson_title: "L2", entry_type: :lesson})

    assert e1.position == 1 and e2.position == 2
    assert e1.progression_module_id == m.id
  end

  test "delete_module reassigns entries to the default bucket and refuses on the bucket",
       %{plan: plan, scope: scope} do
    {:ok, m} = Curriculum.create_module(scope, plan, %{title: "M1"})

    {:ok, _e} =
      Curriculum.add_progression_entry(scope, m, %{lesson_title: "L1", entry_type: :lesson})

    {:ok, bucket} = Curriculum.ensure_default_module(scope, plan)

    assert :ok = Curriculum.delete_module(scope, m)

    [reloaded] =
      Curriculum.list_progression_modules!(plan.id, scope: scope)
      |> Enum.filter(& &1.default?)

    assert reloaded.id == bucket.id
    assert length(reloaded.entries) == 1
    assert {:error, :default_bucket} = Curriculum.delete_module(scope, bucket)
  end

  test "list_progression_modules returns modules ordered with ordered entries", %{
    plan: plan,
    scope: scope
  } do
    {:ok, m1} = Curriculum.create_module(scope, plan, %{title: "M1"})
    {:ok, m2} = Curriculum.create_module(scope, plan, %{title: "M2"})

    {:ok, _} =
      Curriculum.add_progression_entry(scope, m1, %{lesson_title: "L1", entry_type: :lesson})

    mods = Curriculum.list_progression_modules!(plan.id, scope: scope)
    assert Enum.map(mods, & &1.title) == ["M1", "M2"]
    assert [%{lesson_title: "L1"}] = hd(mods).entries
    assert m2.id in Enum.map(mods, & &1.id)
  end

  test "module accepts credit_hours via update", %{plan: plan, scope: scope} do
    {:ok, m} = Curriculum.create_module(scope, plan, %{title: "M1"})

    {:ok, m} =
      m
      |> Ash.Changeset.for_update(:update, %{credit_hours: Decimal.new("11")})
      |> Ash.Changeset.set_tenant(m.workspace_id)
      |> Ash.update(authorize?: false)

    assert Decimal.equal?(m.credit_hours, Decimal.new("11"))
  end

  test "update_module_credit sets the credit", %{plan: plan, scope: scope} do
    {:ok, m} = Curriculum.create_module(scope, plan, %{title: "M1"})
    {:ok, m} = Curriculum.update_module_credit(scope, m, Decimal.new("11"))
    assert Decimal.equal?(m.credit_hours, Decimal.new("11"))
  end

  test "module accepts a sequence_id", %{plan: plan, scope: scope} do
    {:ok, m} = Curriculum.create_module(scope, plan, %{title: "M1"})

    # sequence_id acceptance is exercised more fully in Task 3; here just assert the attribute exists & is nil by default
    assert m.sequence_id == nil
  end

  test "assign_module_sequence sets the module and propagates to its entries", %{
    plan: plan,
    scope: scope
  } do
    seq = seed_sequence(plan)
    {:ok, m} = Curriculum.create_module(scope, plan, %{title: "M1"})

    {:ok, e1} =
      Curriculum.add_progression_entry(scope, m, %{lesson_title: "L1", entry_type: :lesson})

    {:ok, m} = Curriculum.assign_module_sequence(scope, m, seq.id)
    assert m.sequence_id == seq.id
    {:ok, e1} = Curriculum.get_progression_entry(scope, e1.id)
    assert e1.sequence_id == seq.id
  end

  test "a lesson added after assignment inherits the module sequence", %{plan: plan, scope: scope} do
    seq = seed_sequence(plan)
    {:ok, m} = Curriculum.create_module(scope, plan, %{title: "M1"})
    {:ok, m} = Curriculum.assign_module_sequence(scope, m, seq.id)
    {:ok, m} = Curriculum.fetch_owned_module(scope, m.id)

    {:ok, e} =
      Curriculum.add_progression_entry(scope, m, %{lesson_title: "L2", entry_type: :lesson})

    assert e.sequence_id == seq.id
  end

  test "set_entry_completed toggles the flag", %{plan: plan, scope: scope} do
    {:ok, m} = Curriculum.create_module(scope, plan, %{title: "M1"})

    {:ok, e} =
      Curriculum.add_progression_entry(scope, m, %{lesson_title: "L1", entry_type: :lesson})

    {:ok, e} = Curriculum.set_entry_completed(scope, e, true)
    assert e.completed? == true
  end
end
