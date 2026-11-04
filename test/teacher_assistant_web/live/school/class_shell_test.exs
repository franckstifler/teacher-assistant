defmodule TeacherAssistantWeb.School.ClassShellTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Enrollment, Organization, TeacherFixtures}
  alias TeacherAssistantWeb.School.ClassShell

  setup do
    %{scope: scope, workspace: ws} = TeacherFixtures.setup_complete_school_fixture()
    year = Organization.current_academic_year(scope)
    [cg | _] = Enrollment.list_class_groups(scope, year)
    %{scope: scope, ws: ws, cg: cg}
  end

  defp member(scope, roles) do
    TeacherFixtures.member_scope_fixture(scope, %{roles: roles})
  end

  describe "visible_tabs/2" do
    test "an admin sees every tab", %{scope: scope, cg: cg} do
      assert ClassShell.visible_tabs(scope, cg) ==
               [
                 :overview,
                 :students,
                 :teachings,
                 :timetable,
                 :register,
                 :discipline,
                 :results,
                 :fees
               ]
    end

    test "the form master sees every tab", %{scope: scope, cg: cg} do
      fm = member(scope, [:teacher])
      {:ok, _} = Enrollment.set_form_master(scope, cg, fm.current_user.id)
      {:ok, cg} = Enrollment.fetch_owned_class_group(scope, cg.id)

      assert ClassShell.visible_tabs(fm, cg) ==
               [
                 :overview,
                 :students,
                 :teachings,
                 :timetable,
                 :register,
                 :discipline,
                 :results,
                 :fees
               ]
    end

    test "the surveillant général sees the register and discipline only", %{scope: scope, cg: cg} do
      sg = member(scope, [:discipline_master])
      assert ClassShell.visible_tabs(sg, cg) == [:register, :discipline]
    end

    test "a plain member sees nothing", %{scope: scope, cg: cg} do
      assert ClassShell.visible_tabs(member(scope, [:teacher]), cg) == []
    end
  end

  describe "the class page" do
    test "sends the surveillant général to the register tab", %{scope: scope, ws: ws, cg: cg} do
      sg = member(scope, [:discipline_master])

      conn =
        build_conn()
        |> log_in_user(sg.current_user)
        |> Plug.Conn.put_session(:workspace_id, ws.id)

      register = ~p"/school/classes/#{cg.id}/register"

      assert {:error, {:live_redirect, %{to: ^register}}} =
               live(conn, ~p"/school/classes/#{cg.id}")

      {:ok, view, _} = live(conn, register)
      assert has_element?(view, "#class-tab-register[aria-current=page]")
      assert has_element?(view, "#class-tab-discipline")
      refute has_element?(view, "#class-tab-students")
    end

    test "shows every tab to an admin, the current one marked", %{scope: scope, ws: ws, cg: cg} do
      conn =
        build_conn()
        |> log_in_user(scope.current_user)
        |> Plug.Conn.put_session(:workspace_id, ws.id)

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      assert has_element?(view, "#class-tab-teachings[aria-current=page]")

      for tab <- ~w(overview students timetable register discipline results),
          do: assert(has_element?(view, "#class-tab-#{tab}"))

      assert has_element?(view, "#class-cycle", "1er cycle")
    end
  end

  describe "browser tab titles" do
    setup %{scope: scope, ws: ws} do
      conn =
        build_conn()
        |> log_in_user(scope.current_user)
        |> Plug.Conn.put_session(:workspace_id, ws.id)

      %{conn: conn}
    end

    test "a class page names the class, then the tab", %{conn: conn, cg: cg} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      assert page_title(view) =~ "#{cg.label} · Vue d'ensemble"

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/students")
      assert page_title(view) =~ "#{cg.label} · Élèves"

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/fees")
      assert page_title(view) =~ "#{cg.label} · Frais"
    end

    test "a student's page names the student", %{conn: conn, scope: scope, cg: cg} do
      {:ok, student} = Enrollment.add_student(scope, cg, %{full_name: "Awa Mbarga", sex: :f})

      {:ok, view, _} = live(conn, ~p"/school/students/#{student.id}")
      assert page_title(view) =~ "Awa Mbarga"
    end

    test "a school page uses its heading", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/school/sequences")
      assert page_title(view) =~ "Suivi de la saisie des notes"
    end
  end
end
