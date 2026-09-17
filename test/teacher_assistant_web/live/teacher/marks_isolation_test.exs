defmodule TeacherAssistantWeb.Teacher.MarksIsolationTest do
  @moduledoc """
  Intra-school teacher isolation: a teacher may only open the marks/roster of a
  teaching context they are assigned to. Sharing a school workspace must NOT grant
  access to a colleague's subject×class.
  """
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{Assignments, Enrollments}
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Iso"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})

    # Teacher A owns the Maths context.
    teacher_a = member(school, head)
    {:ok, tc_a} = Assignments.assign(cg, teacher_a, %{subject: "Maths"})

    # Teacher B is a member who teaches a DIFFERENT subject (so B passes the
    # teaching-scope guard and reaches mount) but does NOT teach tc_a.
    teacher_b = member(school, head)
    {:ok, _tc_b} = Assignments.assign(cg, teacher_b, %{subject: "Français"})

    conn_b =
      conn |> log_in_user(teacher_b) |> Plug.Conn.put_session(:workspace_id, school.id)

    %{conn_b: conn_b, tc_a: tc_a}
  end

  defp member(school, head) do
    user = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(user.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, user)
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
