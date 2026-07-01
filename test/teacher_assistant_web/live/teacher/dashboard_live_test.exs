defmodule TeacherAssistantWeb.Teacher.DashboardLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "redirects to sign-in when logged out", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/teacher")
  end

  describe "authenticated" do
    setup :register_and_log_in_user

    test "shows setup gate when no academic year", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/teacher")
      assert html =~ "id=\"academic-year-setup-gate\""
    end

    test "shows coverage kpis after setup", %{conn: conn, workspace: ws} do
      {:ok, year} =
        TeacherAssistant.Academics.create_academic_year(ws, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      :ok = TeacherAssistant.Academics.build_default_calendar(year)

      {:ok, ctx} =
        TeacherAssistant.Academics.create_teaching_context(ws, year, %{
          subject: "Maths",
          level: "6ème",
          subsystem: :francophone,
          weekly_hours: 4
        })

      {:ok, _plan} =
        TeacherAssistant.Academics.create_progression_plan(ctx, %{title: "Maths 6ème"})

      {:ok, view, _html} = live(conn, ~p"/teacher")
      assert has_element?(view, "#coverage-kpis")
    end

    test "dashboard links to marks for a context", %{conn: conn, workspace: ws} do
      {:ok, year} =
        TeacherAssistant.Academics.create_academic_year(ws, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      :ok = TeacherAssistant.Academics.build_default_calendar(year)

      {:ok, ctx} =
        TeacherAssistant.Academics.create_teaching_context(ws, year, %{
          subject: "Maths",
          level: "6ème",
          subsystem: :francophone,
          weekly_hours: 4
        })

      {:ok, _plan} =
        TeacherAssistant.Academics.create_progression_plan(ctx, %{title: "Maths 6ème"})

      {:ok, view, _html} = live(conn, ~p"/teacher")

      assert has_element?(
               view,
               ~s(a[href="/teacher/contexts/#{ctx.id}/marks"])
             )

      assert has_element?(
               view,
               ~s(a[href="/teacher/contexts/#{ctx.id}/marks/summary"])
             )
    end

    test "shows the at-a-glance strip and per-card roster/coverage links", %{
      conn: conn,
      workspace: ws
    } do
      {:ok, year} =
        TeacherAssistant.Academics.create_academic_year(ws, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      :ok = TeacherAssistant.Academics.build_default_calendar(year)

      {:ok, ctx} =
        TeacherAssistant.Academics.create_teaching_context(ws, year, %{
          subject: "Maths",
          level: "6ème",
          subsystem: :francophone,
          weekly_hours: 4
        })

      {:ok, plan} =
        TeacherAssistant.Academics.create_progression_plan(ctx, %{title: "Maths 6ème"})

      {:ok, view, _html} = live(conn, ~p"/teacher")

      assert has_element?(view, "#dashboard-stats")
      assert render(element(view, "#dashboard-stats")) =~ "Classes"
      assert has_element?(view, "#kpi-roster-#{plan.id}")
      assert has_element?(view, "#kpi-coverage-#{plan.id}")
    end
  end
end
