defmodule TeacherAssistant.SupportFixturesTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.{Accounts, Attendance, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  test "register_and_log_in_user logs a school head into a setup-complete school", %{
    conn: conn,
    workspace: school,
    actor: head,
    year: year,
    scope: scope
  } do
    assert {:ok, m} = Accounts.fetch_school_membership(school, head)
    assert :head in m.roles
    assert Organization.current_academic_year(school).id == year.id
    assert length(Organization.list_sequences(year)) == 6
    assert Attendance.list_periods(scope) != []
    assert Plug.Conn.get_session(conn, :workspace_id) == school.id
  end

  test "school_teacher_fixture assigns a plain teacher to a class", %{
    scope: scope
  } do
    %{teacher: t, membership: m, class_group: cg, teaching_context: tc} =
      TeacherFixtures.school_teacher_fixture(scope, %{subject: "Anglais"})

    assert m.roles == [:teacher]
    assert tc.teacher_user_id == t.id
    assert tc.class_group_id == cg.id
    assert tc.subject == "Anglais"
  end

  test "assigned_context_fixture builds a context with a real teacher and class", %{
    workspace: school,
    year: year,
    scope: scope
  } do
    tc = TeacherFixtures.assigned_context_fixture(scope, year, %{subject: "SVT"})
    assert tc.subject == "SVT"
    assert tc.teacher_user_id
    assert tc.class_group_id
    {:ok, cg} = Enrollment.fetch_owned_class_group(tc.class_group_id, school)
    assert [_ | _] = Curriculum.list_assignments_for_class(cg)
  end

  describe "scope-aware fixtures" do
    test "school_fixture returns the head's real scope" do
      %{workspace: ws, head_user: head, scope: scope} = TeacherFixtures.school_fixture()

      assert scope.current_user.id == head.id
      assert scope.current_workspace.id == ws.id
      assert :head in scope.current_roles
    end

    test "setup_complete_school_fixture is verified by default and can opt out" do
      assert %{scope: scope} = TeacherFixtures.setup_complete_school_fixture()
      assert TeacherAssistant.Scope.school_verified?(scope)
      assert scope.current_academic_year

      assert %{scope: unverified} =
               TeacherFixtures.setup_complete_school_fixture(%{verified: false})

      refute TeacherAssistant.Scope.school_verified?(unverified)
    end

    test "member_scope_fixture returns a member's scope with the given roles" do
      %{scope: head} = TeacherFixtures.school_fixture()
      bursar = TeacherFixtures.member_scope_fixture(head, %{roles: [:bursar]})

      assert bursar.current_workspace.id == head.current_workspace.id
      assert bursar.current_roles == [:bursar]
      refute bursar.current_user.id == head.current_user.id
    end
  end
end
