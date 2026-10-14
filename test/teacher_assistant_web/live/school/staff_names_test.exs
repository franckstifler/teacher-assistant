defmodule TeacherAssistantWeb.School.StaffNamesTest do
  @moduledoc "Staff are shown by name (their e-mail only when they have none)."
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Curriculum, Enrollment, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    teacher = TeacherFixtures.user_fixture(%{name: "Grace Tabi"})
    TeacherFixtures.member_scope_fixture(scope, %{user: teacher})
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6ème N", level: "6ème"})
    {:ok, _} = Curriculum.assign_teacher(scope, cg, teacher, %{subject: "Anglais"})
    %{teacher: teacher, cg: cg}
  end

  test "Membres shows the name", %{conn: conn, teacher: teacher} do
    {:ok, view, _} = live(conn, ~p"/school/members")
    row = view |> element("[id^='member-row-']", "Grace Tabi") |> render()
    # the name is the row's title; the e-mail is only the contact line under it
    refute row =~ ~r/font-medium">\s*#{Regex.escape(to_string(teacher.email))}\s*</
  end

  test "the class page shows the course teacher and the form-master picker by name",
       %{conn: conn, cg: cg, teacher: teacher} do
    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
    assert html =~ "Grace Tabi"
    # A member without a name (the head here) still shows by e-mail; a named one never does.
    refute html =~ ~r/>\s*#{Regex.escape(to_string(teacher.email))}\s*</
  end

  test "a named member sees their name in the rail and on their printed timetable",
       %{conn: conn, workspace: school, teacher: teacher} do
    conn = Plug.Conn.put_session(log_in_user(conn, teacher), :workspace_id, school.id)

    {:ok, _view, html} = live(conn, ~p"/school/timetable/me")
    assert html =~ "Grace Tabi"

    body = conn |> get(~p"/school/timetable/me/print") |> html_response(200)
    assert body =~ "Grace Tabi"
    refute body =~ to_string(teacher.email)
  end
end
