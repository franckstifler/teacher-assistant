defmodule TeacherAssistantWeb.School.ModulesUiTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Enrollment, Organization, Scope, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{workspace: ws} do
    %{op: %Scope{current_user: TeacherFixtures.admin_user_fixture()}, ws: ws}
  end

  test "a school with no modules still opens its dashboard", %{conn: conn, op: op, ws: ws} do
    {:ok, _} = Organization.set_modules(op, ws, [])
    {:ok, view, _html} = live(conn, ~p"/school")
    refute has_element?(view, "#kpi-calls")
    refute has_element?(view, "#kpi-entry")
  end

  test "the class page hides the tabs of off modules",
       %{conn: conn, op: op, ws: ws, scope: scope} do
    {:ok, _} = Organization.set_modules(op, ws, [:notes])
    [cg | _] = Enrollment.list_class_groups(scope, scope.current_academic_year)
    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}")
    assert has_element?(view, ~s|#class-tabs a[href="/school/classes/#{cg.id}/results"]|)
    refute has_element?(view, ~s|#class-tabs a[href="/school/classes/#{cg.id}/discipline"]|)
    refute has_element?(view, ~s|#class-tabs a[href="/school/classes/#{cg.id}/register"]|)
    refute has_element?(view, "#go-to-photos")
  end

  test "settings lists the active modules, read only", %{conn: conn, op: op, ws: ws} do
    {:ok, _} = Organization.set_modules(op, ws, [:notes, :appel])
    {:ok, view, _html} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#school-module-notes")
    assert has_element?(view, "#school-module-appel")
    refute has_element?(view, "#school-module-frais")
    refute has_element?(view, "#school-modules input")
  end

  test "the bulletin template drops absences and conduct of off modules",
       %{op: op, ws: ws, scope: scope} do
    [cg | _] = Enrollment.list_class_groups(scope, scope.current_academic_year)
    assert :absences in TeacherAssistant.ReportCards.template(scope, cg).elements

    {:ok, ws} = Organization.set_modules(op, ws, [:notes])
    scope = %{scope | current_workspace: ws}
    elements = TeacherAssistant.ReportCards.template(scope, cg).elements
    refute :absences in elements
    refute :conduct in elements
  end

  test "the student profile hides attendance and discipline of off modules",
       %{conn: conn, op: op, ws: ws, scope: scope} do
    [cg | _] = Enrollment.list_class_groups(scope, scope.current_academic_year)
    {:ok, student} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Organization.set_modules(op, ws, [:notes])

    {:ok, view, _html} = live(conn, ~p"/school/students/#{student.id}")
    refute has_element?(view, "#this-year-unjustified")
    refute has_element?(view, "#this-year-consignes")
  end
end
