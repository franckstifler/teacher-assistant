defmodule TeacherAssistant.SupportFixturesTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.{Accounts, Attendance, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  test "register_and_log_in_user logs a school head into a setup-complete school", %{
    conn: conn,
    workspace: school,
    actor: head,
    year: year
  } do
    assert {:ok, m} = Accounts.fetch_school_membership(school, head)
    assert :head in m.roles
    assert Organization.current_academic_year(school).id == year.id
    assert length(Organization.list_sequences(year)) == 6
    assert Attendance.list_periods(school) != []
    assert Plug.Conn.get_session(conn, :workspace_id) == school.id
  end

  test "school_teacher_fixture assigns a plain teacher to a class", %{
    workspace: school,
    actor: head
  } do
    %{teacher: t, membership: m, class_group: cg, teaching_context: tc} =
      TeacherFixtures.school_teacher_fixture(school, head, %{subject: "Anglais"})

    assert m.roles == [:teacher]
    assert tc.teacher_user_id == t.id
    assert tc.class_group_id == cg.id
    assert tc.subject == "Anglais"
  end

  test "assigned_context_fixture builds a context with a real teacher and class", %{
    workspace: school,
    year: year
  } do
    tc = TeacherFixtures.assigned_context_fixture(school, year, %{subject: "SVT"})
    assert tc.subject == "SVT"
    assert tc.teacher_user_id
    assert tc.class_group_id
    {:ok, cg} = Enrollment.fetch_owned_class_group(tc.class_group_id, school)
    assert [_ | _] = Curriculum.list_assignments_for_class(cg)
  end
end
