defmodule TeacherAssistantWeb.NavigationAuthorizationTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "role-aware navigation" do
    setup [:register_and_log_in_user]

    test "admin sees configuration, access control, and teacher tools", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/teacher/marks")

      {:ok, view, _html} = live(conn, ~p"/teacher/attendance")

      assert has_element?(view, "#nav-configuration")
      assert has_element?(view, "#nav-student-access")
      assert has_element?(view, "#nav-grade-intervals")
      assert has_element?(view, "#nav-teacher-tools")
    end

    test "teacher sees teacher tools but not configuration or access control", %{
      conn: conn,
      tenant: tenant
    } do
      teacher = generate(user(tenant: tenant, role: :teacher))
      generate(user_school(tenant: tenant, user_id: teacher.id, role: teacher.role))

      {:ok, view, _html} =
        conn
        |> log_in_user(tenant, teacher)
        |> live(~p"/teacher/attendance")

      assert has_element?(view, "#nav-teacher-tools")
      refute has_element?(view, "#nav-configuration")
      refute has_element?(view, "#nav-student-access")
    end
  end

  describe "route authorization" do
    setup [:register_and_log_in_user]

    test "teacher cannot open configuration pages", %{conn: conn, tenant: tenant} do
      teacher = generate(user(tenant: tenant, role: :teacher))
      generate(user_school(tenant: tenant, user_id: teacher.id, role: teacher.role))

      assert {:error, {:redirect, %{to: "/"}}} =
               conn
               |> log_in_user(tenant, teacher)
               |> live(~p"/configurations/students")
    end

    test "accountant can open student access but not grade intervals", %{
      conn: conn,
      tenant: tenant
    } do
      accountant = generate(user(tenant: tenant, role: :accountant))
      generate(user_school(tenant: tenant, user_id: accountant.id, role: accountant.role))

      accountant_conn = log_in_user(conn, tenant, accountant)

      assert {:ok, _view, _html} = live(accountant_conn, "/configurations/student_access")

      assert {:error, {:redirect, %{to: "/"}}} =
               live(accountant_conn, "/configurations/grade_intervals")
    end
  end
end
