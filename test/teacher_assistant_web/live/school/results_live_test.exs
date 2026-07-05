defmodule TeacherAssistantWeb.School.ResultsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée R"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Academics.build_default_calendar(year)
    [seq | _] = Academics.list_sequences(year)
    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})

    {:ok, a} =
      Academics.create_assessment(tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [student] = Academics.list_students(cg)
    :ok = Academics.upsert_marks(a, [%{student_id: student.id, score: Decimal.new(15)}])
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, seq: seq, student: student, head: head}
  end

  test "renders the ranked results with the moyenne générale", %{conn: conn, cg: cg} do
    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}/results")
    assert html =~ "Awa"
    assert html =~ "15"
  end

  test "cross-school class id redirects", %{conn: conn, head: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, os} = Schools.create_school(other, %{name: "Autre"})

    {:ok, oy} =
      Academics.create_academic_year(os, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} = Academics.create_class_group(os, oy, %{label: "6e Z", level: "6ème"})
    _ = head

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}/results")
  end

  test "a non-admin member is redirected to /school", %{school: school, cg: cg, head: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}/results")
  end
end
