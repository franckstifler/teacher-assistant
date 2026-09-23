defmodule TeacherAssistantWeb.Teacher.RosterLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Curriculum
  setup :register_and_log_in_user

  setup %{workspace: ws} do
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
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    %{ws: ws, year: year, ctx: ctx}
  end

  test "unknown context redirects to setup", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/roster")
  end

  describe "with a linked class group" do
    setup %{ws: ws, year: year, ctx: ctx} do
      {:ok, cg} = Enrollment.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
      {:ok, ctx} = Curriculum.link_class_group(ctx, cg)
      {:ok, s1} = Enrollment.add_student(cg, %{full_name: "Awa", sex: :f})
      {:ok, s2} = Enrollment.add_student(cg, %{full_name: "Beba", sex: :m})
      %{ctx: ctx, cg: cg, s1: s1, s2: s2}
    end

    test "shows girls/boys count and student table", %{conn: conn, ctx: ctx} do
      {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/roster")

      # setup has 1 girl (Awa) + 1 boy (Beba)
      assert has_element?(view, "#roster-count", "1")
      assert render(element(view, "#roster-count")) =~ "Filles"
      assert render(element(view, "#roster-count")) =~ "Garçons"
      assert has_element?(view, "#student-table")
    end

    test "empty roster shows a strong empty state", %{conn: conn, ws: ws, year: year} do
      {:ok, ctx2} =
        Curriculum.create_teaching_context(ws, year, %{
          subject: "PCT",
          level: "3ème",
          subsystem: :francophone,
          weekly_hours: 2
        })

      {:ok, cg2} = Enrollment.create_class_group(ws, year, %{label: "3e P", level: "3ème"})
      {:ok, ctx2} = Curriculum.link_class_group(ctx2, cg2)

      {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx2.id}/roster")
      # apostrophe is HTML-escaped in the rendered title — assert around it
      assert render(view) =~ "Aucun élève pour l"
    end
  end
end
