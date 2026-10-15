defmodule TeacherAssistantWeb.ModuleGuardTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Enrollment, Organization, Scope, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{workspace: ws} do
    %{operator: %Scope{current_user: TeacherFixtures.admin_user_fixture()}, ws: ws}
  end

  test "a screen of an off module is refused when typed", %{conn: conn, operator: op, ws: ws} do
    {:ok, _} = Organization.set_modules(op, ws, [:notes])

    assert {:error, {:live_redirect, %{to: "/school", flash: flash}}} =
             live(conn, ~p"/school/sanctions")

    assert flash["error"] =~ "pas activé"
  end

  test "a screen of an on module opens", %{conn: conn, operator: op, ws: ws} do
    {:ok, _} = Organization.set_modules(op, ws, [:discipline])
    assert {:ok, _view, _html} = live(conn, ~p"/school/sanctions")
  end

  test "a core screen opens with no module", %{conn: conn, operator: op, ws: ws} do
    {:ok, _} = Organization.set_modules(op, ws, [])
    assert {:ok, _view, _html} = live(conn, ~p"/school/classes")
  end

  test "a print route of an off module redirects home",
       %{conn: conn, operator: op, ws: ws, scope: scope} do
    {:ok, _} = Organization.set_modules(op, ws, [:notes])
    [cg | _] = Enrollment.list_class_groups(scope, scope.current_academic_year)
    conn = get(conn, ~p"/school/classes/#{cg.id}/timetable/print")
    assert redirected_to(conn) == "/school"
  end

  test "a suspended school's member lands on the suspended page",
       %{conn: conn, operator: op, ws: ws} do
    {:ok, _} = Organization.suspend_school(op, ws, "Impayé")

    assert {:error, {:live_redirect, %{to: "/school/suspended"}}} =
             live(conn, ~p"/school/classes")

    {:ok, view, _html} = live(conn, ~p"/school/suspended")
    assert has_element?(view, "#suspension-reason", "Impayé")
  end

  test "a suspended school's print route redirects", %{conn: conn, operator: op, ws: ws} do
    {:ok, _} = Organization.suspend_school(op, ws, "Impayé")
    conn = get(conn, ~p"/school/logo")
    assert redirected_to(conn) == "/school/suspended"
  end

  test "the suspended page sends an active school's member home", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/suspended")
  end

  test "bulletin verification ignores suspension", %{operator: op, ws: ws} do
    {:ok, _} = Organization.suspend_school(op, ws, "Impayé")
    conn = get(Phoenix.ConnTest.build_conn(), ~p"/verify/bulletin/unknown-token")
    refute conn.status == 302 and redirected_to(conn) == "/school/suspended"
  end

  test "a member switches from a suspended school to another",
       %{conn: conn, operator: op, ws: ws, actor: head} do
    %{workspace: other} = TeacherFixtures.school_fixture(%{head_user: head})
    TeacherFixtures.complete_school_setup!(school_scope(head, other))
    {:ok, _} = Organization.suspend_school(op, ws, "Impayé")

    conn = get(conn, ~p"/workspaces/select/#{other.id}")
    assert {:ok, _view, _html} = live(recycle(conn), ~p"/school/classes")
  end
end
