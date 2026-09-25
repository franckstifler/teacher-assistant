defmodule TeacherAssistantWeb.Teacher.RosterLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.TeacherFixtures
  setup :register_and_log_in_user

  test "unknown context redirects to setup", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/roster")
  end

  describe "with a linked class group" do
    setup %{workspace: ws, year: year, actor: head, scope: scope} do
      tc =
        TeacherFixtures.assigned_context_fixture(scope, year, %{
          subject: "Maths",
          level: "3ème",
          teacher: head
        })

      {:ok, cg} = Enrollment.fetch_owned_class_group(tc.class_group_id, ws)
      {:ok, s1} = Enrollment.add_student(cg, %{full_name: "Awa", sex: :f})
      {:ok, s2} = Enrollment.add_student(cg, %{full_name: "Beba", sex: :m})
      %{ctx: tc, cg: cg, s1: s1, s2: s2}
    end

    test "shows girls/boys count and student table", %{conn: conn, ctx: ctx} do
      {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx.id}/roster")

      # setup has 1 girl (Awa) + 1 boy (Beba)
      assert has_element?(view, "#roster-count", "1")
      assert render(element(view, "#roster-count")) =~ "Filles"
      assert render(element(view, "#roster-count")) =~ "Garçons"
      assert has_element?(view, "#student-table")
    end

    test "empty roster shows a strong empty state", %{
      conn: conn,
      year: year,
      actor: head,
      scope: scope
    } do
      ctx2 =
        TeacherFixtures.assigned_context_fixture(scope, year, %{
          subject: "PCT",
          level: "3ème",
          teacher: head
        })

      {:ok, view, _html} = live(conn, ~p"/teacher/contexts/#{ctx2.id}/roster")
      # apostrophe is HTML-escaped in the rendered title — assert around it
      assert render(view) =~ "Aucun élève pour l"
    end
  end
end
