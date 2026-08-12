defmodule TeacherAssistant.Academics.ApplyLayoutTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "Y",
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

    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "P"})
    {:ok, m1} = Academics.create_module(plan, %{title: "M1"})
    {:ok, m2} = Academics.create_module(plan, %{title: "M2"})
    {:ok, a} = Academics.add_progression_entry(m1, %{lesson_title: "A", entry_type: :lesson})
    {:ok, b} = Academics.add_progression_entry(m1, %{lesson_title: "B", entry_type: :lesson})
    {:ok, c} = Academics.add_progression_entry(m2, %{lesson_title: "C", entry_type: :lesson})
    %{plan: plan, m1: m1, m2: m2, a: a, b: b, c: c}
  end

  test "reorders modules and moves a lesson across modules", %{
    plan: plan,
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

    assert {:ok, :applied} = Academics.apply_layout(plan, layout)

    mods = Academics.list_progression_modules(plan)
    assert Enum.map(mods, & &1.title) == ["M2", "M1"]
    [first, second] = mods
    assert Enum.map(first.entries, & &1.lesson_title) == ["C", "B"]
    assert Enum.map(second.entries, & &1.lesson_title) == ["A"]
  end

  test "rejects a layout missing an entry", %{plan: plan, m1: m1, m2: m2, a: a, c: c} do
    layout = [
      %{"module_id" => m1.id, "entry_ids" => [a.id]},
      %{"module_id" => m2.id, "entry_ids" => [c.id]}
    ]

    assert {:error, :invalid_layout} = Academics.apply_layout(plan, layout)
  end

  test "rejects a foreign module id", %{plan: plan, m1: m1, a: a, b: b, c: c} do
    layout = [%{"module_id" => Ecto.UUID.generate(), "entry_ids" => [a.id, b.id, c.id]}]
    assert {:error, :invalid_layout} = Academics.apply_layout(plan, layout)
  end

  test "rejects a layout that duplicates one entry id and drops another", %{
    plan: plan,
    m1: m1,
    m2: m2,
    a: a,
    c: c
  } do
    layout = [
      %{"module_id" => m1.id, "entry_ids" => [a.id, a.id]},
      %{"module_id" => m2.id, "entry_ids" => [c.id]}
    ]

    assert {:error, :invalid_layout} = Academics.apply_layout(plan, layout)

    mods = Academics.list_progression_modules(plan)
    assert Enum.map(mods, & &1.title) == ["M1", "M2"]
    [first, _second] = mods
    assert Enum.map(first.entries, & &1.lesson_title) == ["A", "B"]
  end

  test "rejects a layout with an extra duplicate entry id", %{
    plan: plan,
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

    assert {:error, :invalid_layout} = Academics.apply_layout(plan, layout)

    mods = Academics.list_progression_modules(plan)
    assert Enum.map(mods, & &1.title) == ["M1", "M2"]
    [first, second] = mods
    assert Enum.map(first.entries, & &1.lesson_title) == ["A", "B"]
    assert Enum.map(second.entries, & &1.lesson_title) == ["C"]
  end
end
