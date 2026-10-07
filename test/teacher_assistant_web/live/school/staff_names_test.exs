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
    row = view |> element("tr", "Grace Tabi") |> render()
    refute row =~ "<td>#{teacher.email}</td>"
  end

  test "the class page shows the course teacher and the form-master picker by name",
       %{conn: conn, cg: cg, teacher: teacher} do
    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}")
    assert html =~ "Grace Tabi"
    # A member without a name (the head here) still shows by e-mail; a named one never does.
    refute html =~ ~r/>\s*#{Regex.escape(to_string(teacher.email))}\s*</
  end
end
