defmodule TeacherAssistantWeb.Teacher.RosterLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
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
        level: "3ème",
        subsystem: :francophone,
        weekly_hours: 4
      })

    %{ws: ws, year: year, ctx: ctx}
  end

  test "creates a class group then adds a student", %{conn: conn, ctx: ctx} do
    {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/roster")

    view
    |> form("#roster-create-class-form", class_group: %{label: "3e M2", level: "3ème"})
    |> render_submit()

    view
    |> form("#student-form", student: %{full_name: "Awa Bello", sex: "f"})
    |> render_submit()

    assert render(view) =~ "Awa Bello"
  end

  test "unknown context redirects to setup", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/teacher/setup"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/roster")
  end

  describe "with a linked class group" do
    setup %{ws: ws, year: year, ctx: ctx} do
      {:ok, cg} = Academics.create_class_group(ws, year, %{label: "3e M2", level: "3ème"})
      {:ok, ctx} = Academics.link_class_group(ctx, cg)
      {:ok, s1} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
      {:ok, s2} = Academics.add_student(cg, %{full_name: "Beba", sex: :m})
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
        Academics.create_teaching_context(ws, year, %{
          subject: "PCT",
          level: "3ème",
          subsystem: :francophone,
          weekly_hours: 2
        })

      {:ok, cg2} = Academics.create_class_group(ws, year, %{label: "3e P", level: "3ème"})
      {:ok, ctx2} = Academics.link_class_group(ctx2, cg2)

      {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx2.id}/roster")
      # apostrophe is HTML-escaped in the rendered title — assert around it
      assert render(view) =~ "Aucun élève pour l"
    end

    test "deleting a student offers undo, undo restores", %{conn: conn, ctx: ctx, s1: s1} do
      {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/roster")

      view |> element("#student-delete-#{s1.id}") |> render_click()
      refute has_element?(view, "#student-row-#{s1.id}")
      assert has_element?(view, "#student-undo", "Annuler")

      view |> element("#student-undo") |> render_click()
      # restored student has a new id; assert by name and that the undo bar is gone
      assert render(element(view, "#student-table")) =~ s1.full_name
      refute has_element?(view, "#student-undo")
    end
  end
end
