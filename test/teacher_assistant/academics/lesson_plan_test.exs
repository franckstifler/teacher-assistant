defmodule TeacherAssistant.Academics.LessonPlanTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, head_user: head, year: year, scope: scope} =
      TeacherFixtures.setup_complete_school_fixture()

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})

    ctx =
      TeacherFixtures.assigned_context_fixture(scope, year, %{
        subject: "Maths",
        level: "6ème",
        teacher: head,
        class_group: cg
      })

    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Beba", sex: :m})
    {:ok, plan} = Curriculum.create_progression_plan(scope, ctx, %{title: "Plan"})

    {:ok, m1} = Curriculum.create_module(scope, plan, %{title: "M1"})

    {:ok, entry} =
      Curriculum.add_progression_entry(scope, m1, %{
        lesson_title: "Les entiers",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson,
        competence_visee: "Résoudre un problème additif"
      })

    %{ws: ws, scope: scope, entry: entry, ctx: ctx}
  end

  test "fetch_owned_entry_with_context returns derived cartouche", %{
    entry: entry,
    scope: scope
  } do
    assert {:ok, ctx_bundle} = Curriculum.fetch_owned_entry_with_context(scope, entry.id)
    assert ctx_bundle.entry.id == entry.id
    assert ctx_bundle.ctx.subject == "Maths"
    assert ctx_bundle.effectif == 2
    assert ctx_bundle.year.name == "Année de référence"
  end

  test "fetch_owned_entry_with_context rejects a foreign entry (IDOR)", %{entry: entry} do
    %{scope: other_scope} = TeacherFixtures.school_fixture()
    assert {:error, _} = Curriculum.fetch_owned_entry_with_context(other_scope, entry.id)
  end

  test "ensure_lesson_plan seeds header from the entry and is idempotent", %{
    entry: entry,
    ctx: ctx,
    scope: scope
  } do
    assert {:ok, lp} = Curriculum.ensure_lesson_plan(scope, entry, ctx)
    assert lp.titre == "Les entiers"
    assert lp.competence_attendue == "Résoudre un problème additif"
    # 2 planned hours => 120 minutes
    assert lp.duration_minutes == 120

    assert {:ok, lp2} = Curriculum.ensure_lesson_plan(scope, entry, ctx)
    assert lp2.id == lp.id
  end

  test "get_lesson_plan_for_entry returns nil before creation", %{entry: entry, scope: scope} do
    assert Curriculum.get_lesson_plan_for_entry(scope, entry.id) == nil
  end

  test "update_lesson_plan persists a single field", %{entry: entry, ctx: ctx, scope: scope} do
    {:ok, lp} = Curriculum.ensure_lesson_plan(scope, entry, ctx)

    {:ok, lp} =
      Curriculum.update_lesson_plan(lp, %{situation_probleme: "Au marché…"}, scope: scope)

    assert lp.situation_probleme == "Au marché…"
  end

  test "ensure_lesson_plan is safe under concurrent first-open", %{
    entry: entry,
    ctx: ctx,
    scope: scope
  } do
    # allow spawned tasks to use this test's sandboxed connection
    parent = self()

    results =
      1..8
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(TeacherAssistant.Repo, parent, self())
          Curriculum.ensure_lesson_plan(scope, entry, ctx)
        end)
      end)
      |> Enum.map(&Task.await/1)

    # every caller gets {:ok, plan} — no {:error, _}, no crash
    assert Enum.all?(results, fn
             {:ok, %TeacherAssistant.Academics.LessonPlan{}} -> true
             _ -> false
           end)

    # exactly one distinct fiche id across all callers
    ids = results |> Enum.map(fn {:ok, lp} -> lp.id end) |> Enum.uniq()
    assert length(ids) == 1
  end
end
