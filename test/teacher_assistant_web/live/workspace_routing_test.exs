defmodule TeacherAssistantWeb.WorkspaceRoutingTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  alias TeacherAssistant.Accounts.Workspaces

  describe "workspace routing" do
    test "authenticated user without selected workspace is sent to workspace selection", %{
      conn: conn
    } do
      user = generate(user_without_school())

      assert {:error, {:redirect, %{to: "/workspaces"}}} =
               conn
               |> log_in_user_without_workspace(user)
               |> live(~p"/teacher/attendance")
    end

    test "role checks use selected membership role instead of global user role", %{conn: conn} do
      school = generate(school())
      user = generate(user_without_school(role: :teacher))
      generate(user_school(tenant: school, user_id: user.id, role: :admin))

      {:ok, view, _html} =
        conn
        |> log_in_user(school, user)
        |> live(~p"/configurations/students")

      assert has_element?(view, "#nav-configuration")
    end

    test "year-required teacher routes redirect to setup when no active academic year exists", %{
      conn: conn
    } do
      user = generate(user_without_school())
      workspace = Workspaces.ensure_personal_workspace!(user)

      assert {:error, {:redirect, %{to: "/setup/academic-year"}}} =
               conn
               |> log_in_user(workspace, user)
               |> live(~p"/teacher/progression")
    end

    test "personal workspace cannot open school-only configuration", %{conn: conn} do
      user = generate(user_without_school())
      workspace = Workspaces.ensure_personal_workspace!(user)

      assert {:error, {:redirect, %{to: "/workspaces"}}} =
               conn
               |> log_in_user(workspace, user)
               |> live(~p"/configurations/students")
    end

    test "academic year setup creates an active year for the selected workspace", %{conn: conn} do
      user = generate(user_without_school())
      workspace = Workspaces.ensure_personal_workspace!(user)

      {:ok, view, _html} =
        conn
        |> log_in_user(workspace, user)
        |> live(~p"/setup/academic-year")

      assert has_element?(view, "#academic-year-setup-form")

      assert {:error, {:live_redirect, %{to: "/teacher/progression"}}} =
               view
               |> form("#academic-year-setup-form",
                 setup: %{
                   name: "2026-2027",
                   start_date: "2026-09-01",
                   end_date: "2027-06-30",
                   term_1_name: "Term 1",
                   term_2_name: "Term 2",
                   term_3_name: "Term 3"
                 }
               )
               |> render_submit()

      scope = Workspaces.scope_for!(user, workspace.id)
      assert scope.current_academic_year.name == "2026-2027"
    end
  end

  defp log_in_user_without_workspace(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end
end
