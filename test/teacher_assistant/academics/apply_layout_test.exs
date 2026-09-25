defmodule TeacherAssistant.Academics.ApplyLayoutTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{head_user: head, year: year, scope: scope} =
      TeacherFixtures.setup_complete_school_fixture()

    ctx =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "6ème",
        teacher: head
      })

    {:ok, plan} = Curriculum.create_progression_plan(scope, ctx, %{title: "P"})
    {:ok, m1} = Curriculum.create_module(scope, plan, %{title: "M1"})
    {:ok, m2} = Curriculum.create_module(scope, plan, %{title: "M2"})

    {:ok, a} =
      Curriculum.add_progression_entry(scope, m1, %{lesson_title: "A", entry_type: :lesson})

    {:ok, b} =
      Curriculum.add_progression_entry(scope, m1, %{lesson_title: "B", entry_type: :lesson})

    {:ok, c} =
      Curriculum.add_progression_entry(scope, m2, %{lesson_title: "C", entry_type: :lesson})

    %{plan: plan, scope: scope, m1: m1, m2: m2, a: a, b: b, c: c}
  end

  test "reorders modules and moves a lesson across modules", %{
    plan: plan,
    scope: scope,
    m1: m1,
    m2: m2,
    a: a,
    b: b,
    c: c
  } do
    layout = [
      %{"module_id" => m2.id, "entry_ids" => [c.id, b.id]},
      %{"module_id" => m1.id, "entry_ids" => [a.id]}
    ]

    assert {:ok, :applied} = Curriculum.apply_layout(scope, plan, layout)

    mods = Curriculum.list_progression_modules!(plan.id, scope: scope)
    assert Enum.map(mods, & &1.title) == ["M2", "M1"]
    [first, second] = mods
    assert Enum.map(first.entries, & &1.lesson_title) == ["C", "B"]
    assert Enum.map(second.entries, & &1.lesson_title) == ["A"]
  end

  test "rejects a layout missing an entry", %{
    plan: plan,
    scope: scope,
    m1: m1,
    m2: m2,
    a: a,
    c: c
  } do
    layout = [
      %{"module_id" => m1.id, "entry_ids" => [a.id]},
      %{"module_id" => m2.id, "entry_ids" => [c.id]}
    ]

    assert {:error, :invalid_layout} = Curriculum.apply_layout(scope, plan, layout)
  end

  test "rejects a foreign module id", %{plan: plan, scope: scope, a: a, b: b, c: c} do
    layout = [%{"module_id" => Ecto.UUID.generate(), "entry_ids" => [a.id, b.id, c.id]}]
    assert {:error, :invalid_layout} = Curriculum.apply_layout(scope, plan, layout)
  end

  test "rejects a layout that duplicates one entry id and drops another", %{
    plan: plan,
    scope: scope,
    m1: m1,
    m2: m2,
    a: a,
    c: c
  } do
    layout = [
      %{"module_id" => m1.id, "entry_ids" => [a.id, a.id]},
      %{"module_id" => m2.id, "entry_ids" => [c.id]}
    ]

    assert {:error, :invalid_layout} = Curriculum.apply_layout(scope, plan, layout)

    mods = Curriculum.list_progression_modules!(plan.id, scope: scope)
    assert Enum.map(mods, & &1.title) == ["M1", "M2"]
    [first, _second] = mods
    assert Enum.map(first.entries, & &1.lesson_title) == ["A", "B"]
  end

  test "rejects a layout with an extra duplicate entry id", %{
    plan: plan,
    scope: scope,
    m1: m1,
    m2: m2,
    a: a,
    b: b,
    c: c
  } do
    layout = [
      %{"module_id" => m1.id, "entry_ids" => [a.id, b.id]},
      %{"module_id" => m2.id, "entry_ids" => [c.id, c.id]}
    ]

    assert {:error, :invalid_layout} = Curriculum.apply_layout(scope, plan, layout)

    mods = Curriculum.list_progression_modules!(plan.id, scope: scope)
    assert Enum.map(mods, & &1.title) == ["M1", "M2"]
    [first, second] = mods
    assert Enum.map(first.entries, & &1.lesson_title) == ["A", "B"]
    assert Enum.map(second.entries, & &1.lesson_title) == ["C"]
  end
end
