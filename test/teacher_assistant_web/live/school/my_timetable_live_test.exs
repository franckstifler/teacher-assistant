defmodule TeacherAssistantWeb.School.MyTimetableLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée T"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})

    :ok = Timetables.build_default_periods(school)
    period = Timetables.list_periods(school) |> Enum.find(&(&1.kind == :lesson))

    {:ok, _slot} =
      Timetables.place_slot(cg, %{day: :monday, period_id: period.id, teaching_context_id: tc.id})

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      school: school,
      year: year,
      cg: cg,
      tc: tc,
      period: period,
      head: head
    }
  end

  test "a teacher with placed slots sees class + subject in their cell", %{
    conn: conn,
    cg: cg,
    period: period
  } do
    {:ok, _view, html} = live(conn, ~p"/school/timetable/me")

    assert html =~ "Mon emploi du temps"
    assert html =~ period.label
    assert html =~ "Lundi"
    assert html =~ "Samedi"
    assert html =~ cg.label
    assert html =~ "Maths"
  end

  test "a member who teaches nothing sees an empty grid and empty state", %{
    school: school,
    head: head
  } do
    member = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(member.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, member)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, member.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, _view, html} = live(conn, ~p"/school/timetable/me")

    refute html =~ "Maths"
    assert html =~ "vide" or html =~ "empty" or html =~ "aucun" or html =~ "Aucun"
  end

  test "a non-school scope is redirected to /teacher", %{} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)

    assert {:error, {:live_redirect, %{to: "/teacher"}}} =
             live(conn, ~p"/school/timetable/me")
  end
end
