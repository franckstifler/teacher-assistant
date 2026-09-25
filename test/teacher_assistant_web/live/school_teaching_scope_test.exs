defmodule TeacherAssistantWeb.SchoolTeachingScopeTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "Lycée G"})
    scope = school_scope(user, school)

    {:ok, year} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, user: user, scope: scope}
  end

  test "a member without assignments is bounced from teaching pages to /school", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/roster")
  end

  test "an assigned teacher reaches the roster under school scope", ctx do
    %{conn: conn, cg: cg, user: user, scope: scope} = ctx
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, user, %{subject: "Maths"})
    assert {:ok, _view, html} = live(conn, ~p"/teacher/contexts/#{tc.id}/roster")
    assert html =~ "Maths"
  end
end
