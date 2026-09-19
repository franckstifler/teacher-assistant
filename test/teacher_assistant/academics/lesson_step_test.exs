defmodule TeacherAssistant.Academics.LessonStepTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()
    ws = Organization.ensure_personal_workspace!(user)

    {:ok, year} =
      Organization.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ctx} =
      Curriculum.create_teaching_context(ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, plan} = Curriculum.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, m1} = Curriculum.create_module(plan, %{title: "M1"})

    {:ok, entry} =
      Curriculum.add_progression_entry(m1, %{
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    {:ok, lp} = Curriculum.ensure_lesson_plan(entry, ctx)
    %{ws: ws, lp: lp}
  end

  test "add appends steps in order", %{lp: lp} do
    {:ok, s1} = Curriculum.add_lesson_step(lp, %{etape: "Découverte"})
    {:ok, s2} = Curriculum.add_lesson_step(lp, %{etape: "Analyse"})

    assert s1.position == 1
    assert s2.position == 2
    assert Enum.map(Curriculum.list_lesson_steps!(lp.id), & &1.etape) == ["Découverte", "Analyse"]
  end

  test "move down then up swaps order and no-ops at the ends", %{lp: lp} do
    {:ok, s1} = Curriculum.add_lesson_step(lp, %{etape: "A"})
    {:ok, s2} = Curriculum.add_lesson_step(lp, %{etape: "B"})

    {:ok, _} = Curriculum.move_lesson_step(s1, :down)
    assert Enum.map(Curriculum.list_lesson_steps!(lp.id), & &1.etape) == ["B", "A"]

    # s2 is now first; moving it up is a no-op-free swap back
    [first, _second] = Curriculum.list_lesson_steps!(lp.id)
    {:ok, _} = Curriculum.move_lesson_step(first, :up)
    assert Enum.map(Curriculum.list_lesson_steps!(lp.id), & &1.etape) == ["B", "A"]

    _ = s2
  end

  test "update and delete a step", %{lp: lp} do
    {:ok, s} = Curriculum.add_lesson_step(lp, %{etape: "X"})
    {:ok, s} = Curriculum.update_lesson_step(s, %{contenus: "les nombres"})
    assert s.contenus == "les nombres"

    :ok = Curriculum.delete_lesson_step(s)
    assert Curriculum.list_lesson_steps!(lp.id) == []
  end

  test "fetch_owned_lesson_step rejects a step from another plan", %{lp: lp, ws: ws} do
    {:ok, s} = Curriculum.add_lesson_step(lp, %{etape: "X"})

    {:ok, year} = {:ok, Organization.current_academic_year(ws)}

    {:ok, ctx2} =
      Curriculum.create_teaching_context(ws, year, %{
        subject: "PCT",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 2
      })

    {:ok, plan2} = Curriculum.create_progression_plan(ctx2, %{title: "P2"})

    {:ok, m} = Curriculum.create_module(plan2, %{title: "M"})

    {:ok, entry2} =
      Curriculum.add_progression_entry(m, %{
        lesson_title: "L",
        planned_hours: Decimal.new("1"),
        entry_type: :lesson
      })

    {:ok, other_lp} = Curriculum.ensure_lesson_plan(entry2, ctx2)

    assert {:error, :not_found} = Curriculum.fetch_owned_lesson_step(s.id, other_lp)
    assert {:ok, _} = Curriculum.fetch_owned_lesson_step(s.id, lp)
  end
end
