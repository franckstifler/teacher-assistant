defmodule TeacherAssistantWeb.Teacher.MarksIsolationTest do
  @moduledoc """
  Intra-school teacher isolation: a teacher may only open the marks/roster of a
  teaching context they are assigned to. Sharing a school workspace must NOT grant
  access to a colleague's subject×class.
  """
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée Iso"})

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})

    # Teacher A owns the Maths context.
    teacher_a = member(scope)
    {:ok, tc_a} = Curriculum.assign_teacher(scope, cg, teacher_a, %{subject: "Maths"})

    # Teacher B is a member who teaches a DIFFERENT subject (so B passes the
    # teaching-scope guard and reaches mount) but does NOT teach tc_a.
    teacher_b = member(scope)
    {:ok, _tc_b} = Curriculum.assign_teacher(scope, cg, teacher_b, %{subject: "Français"})

    conn_b =
      conn |> log_in_user(teacher_b) |> Plug.Conn.put_session(:workspace_id, school.id)

    %{conn_b: conn_b, tc_a: tc_a}
  end

  defp member(scope) do
    user = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(scope, %{email: to_string(user.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: user}, inv.token)
    user
  end

  test "a teacher cannot open a colleague's marks page", %{conn_b: conn_b, tc_a: tc_a} do
    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn_b, ~p"/teacher/contexts/#{tc_a.id}/marks")

    refute to =~ tc_a.id
  end

  test "a teacher cannot open a colleague's séquence summary", %{conn_b: conn_b, tc_a: tc_a} do
    assert {:error, {:live_redirect, _}} =
             live(conn_b, ~p"/teacher/contexts/#{tc_a.id}/marks/summary")
  end

  test "a teacher cannot open a colleague's roster", %{conn_b: conn_b, tc_a: tc_a} do
    assert {:error, {:live_redirect, _}} =
             live(conn_b, ~p"/teacher/contexts/#{tc_a.id}/roster")
  end
end
