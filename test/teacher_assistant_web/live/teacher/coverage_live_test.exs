defmodule TeacherAssistantWeb.Teacher.CoverageLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.TeacherFixtures
  setup :register_and_log_in_user

  setup %{workspace: ws} do
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

    {:ok, e1} =
      Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "L1",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    {:ok, _e2} =
      Academics.add_progression_entry(plan, %{
        module: "M1",
        lesson_title: "L2",
        planned_hours: Decimal.new("2"),
        entry_type: :lesson
      })

    {:ok, _log} =
      Academics.log_teaching(ws, %{
        date: ~D[2025-09-15],
        content_taught: "x",
        hours: Decimal.new("2"),
        status: :done,
        progression_entry_id: e1.id
      })

    %{plan: plan}
  end

  test "redirects to /teacher when accessing another user's coverage (IDOR)", %{conn: conn} do
    other_user = TeacherFixtures.user_fixture()
    other_ws = Academics.ensure_personal_workspace!(other_user)

    {:ok, year} =
      Academics.create_academic_year(other_ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ctx} =
      Academics.create_teaching_context(other_ws, year, %{
        subject: "Maths",
        level: "6ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    {:ok, other_plan} = Academics.create_progression_plan(ctx, %{title: "Other Plan"})

    assert {:error, {:live_redirect, %{to: "/teacher"}}} =
             live(conn, ~p"/teacher/plans/#{other_plan.id}/coverage")
  end

  test "shows 50% coverage and one uncovered entry", %{conn: conn, plan: plan} do
    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}/coverage")
    assert has_element?(view, "#coverage-summary")
    assert render(view) =~ "50%"
    assert has_element?(view, "#uncovered-entries")
  end

  test "shows per-séquence breakdown with hours", %{conn: conn, plan: plan} do
    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}/coverage")

    assert has_element?(view, "#coverage-by-sequence")
    # entries in this setup carry no séquence -> the "Sans séquence" row with hours
    breakdown = render(element(view, "#coverage-by-sequence"))
    assert breakdown =~ "Sans séquence"
    assert breakdown =~ "2h / 4h"
  end

  test "uncovered rows show covered/planned hours", %{conn: conn, plan: plan} do
    {:ok, view, _html} = live(conn, ~p"/teacher/plans/#{plan.id}/coverage")

    assert render(element(view, "#uncovered-entries")) =~ "0h / 2h"
  end
end
