defmodule TeacherAssistant.Academics.LessonPlanTest do
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

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    {:ok, ctx} = Academics.link_class_group(ctx, cg)
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Beba", sex: :m})
    {:ok, plan} = Academics.create_progression_plan(ctx, %{title: "Plan"})

    {:ok, entry} =
      Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson,
        competence_visee: "Résoudre un problème additif"
      })

    %{ws: ws, entry: entry, ctx: ctx}
  end

  test "fetch_owned_entry_with_context returns derived cartouche", %{ws: ws, entry: entry} do
    assert {:ok, ctx_bundle} = Academics.fetch_owned_entry_with_context(entry.id, ws)
    assert ctx_bundle.entry.id == entry.id
    assert ctx_bundle.ctx.subject == "Maths"
    assert ctx_bundle.effectif == 2
    assert ctx_bundle.year.name == "2025-2026"
  end

  test "fetch_owned_entry_with_context rejects a foreign entry (IDOR)", %{entry: entry} do
    other = Academics.ensure_personal_workspace!(TeacherFixtures.user_fixture())
    assert {:error, _} = Academics.fetch_owned_entry_with_context(entry.id, other)
  end

  test "ensure_lesson_plan seeds header from the entry and is idempotent", %{
    entry: entry,
    ctx: ctx
  } do
    assert {:ok, lp} = Academics.ensure_lesson_plan(entry, ctx)
    assert lp.titre == "Les entiers"
    assert lp.competence_attendue == "Résoudre un problème additif"
    # 2 planned hours => 120 minutes
    assert lp.duration_minutes == 120

    assert {:ok, lp2} = Academics.ensure_lesson_plan(entry, ctx)
    assert lp2.id == lp.id
  end

  test "get_lesson_plan_for_entry returns nil before creation", %{entry: entry} do
    assert Academics.get_lesson_plan_for_entry(entry.id) == nil
  end

  test "update_lesson_plan persists a single field", %{entry: entry, ctx: ctx} do
    {:ok, lp} = Academics.ensure_lesson_plan(entry, ctx)
    {:ok, lp} = Academics.update_lesson_plan(lp, %{situation_probleme: "Au marché…"})
    assert lp.situation_probleme == "Au marché…"
  end
end
