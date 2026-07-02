defmodule TeacherAssistant.Academics.LessonStepTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics
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
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    {:ok, lp} = Academics.ensure_lesson_plan(entry, ctx)
    %{ws: ws, lp: lp}
  end

  test "add appends steps in order", %{lp: lp} do
    {:ok, s1} = Academics.add_lesson_step(lp, %{etape: "Découverte"})
    {:ok, s2} = Academics.add_lesson_step(lp, %{etape: "Analyse"})

    assert s1.position == 1
    assert s2.position == 2
    assert Enum.map(Academics.list_lesson_steps(lp), & &1.etape) == ["Découverte", "Analyse"]
  end

  test "move down then up swaps order and no-ops at the ends", %{lp: lp} do
    {:ok, s1} = Academics.add_lesson_step(lp, %{etape: "A"})
    {:ok, s2} = Academics.add_lesson_step(lp, %{etape: "B"})

    {:ok, _} = Academics.move_lesson_step(s1, :down)
    assert Enum.map(Academics.list_lesson_steps(lp), & &1.etape) == ["B", "A"]

    # s2 is now first; moving it up is a no-op-free swap back
    [first, _second] = Academics.list_lesson_steps(lp)
    {:ok, _} = Academics.move_lesson_step(first, :up)
    assert Enum.map(Academics.list_lesson_steps(lp), & &1.etape) == ["B", "A"]

    _ = s2
  end

  test "update and delete a step", %{lp: lp} do
    {:ok, s} = Academics.add_lesson_step(lp, %{etape: "X"})
    {:ok, s} = Academics.update_lesson_step(s, %{contenus: "les nombres"})
    assert s.contenus == "les nombres"

    :ok = Academics.delete_lesson_step(s)
    assert Academics.list_lesson_steps(lp) == []
  end

  test "fetch_owned_lesson_step rejects a step from another plan", %{lp: lp, ws: ws} do
    {:ok, s} = Academics.add_lesson_step(lp, %{etape: "X"})

    {:ok, year} = {:ok, Academics.current_academic_year(ws)}

    {:ok, ctx2} =
      Academics.create_teaching_context(ws, year, %{
        subject: "PCT",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 2
      })

    {:ok, plan2} = Academics.create_progression_plan(ctx2, %{title: "P2"})

    {:ok, entry2} =
      Academics.add_progression_entry(plan2, %{
        module: "M",
        lesson_title: "L",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    {:ok, other_lp} = Academics.ensure_lesson_plan(entry2, ctx2)

    assert {:error, :not_found} = Academics.fetch_owned_lesson_step(s.id, other_lp)
    assert {:ok, _} = Academics.fetch_owned_lesson_step(s.id, lp)
  end
end
