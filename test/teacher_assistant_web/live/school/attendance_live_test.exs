defmodule TeacherAssistantWeb.School.AttendanceLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Attendance
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

    # Monday, so the slot's day_of_week matches.
    date = ~D[2025-09-08]

    {:ok, _slot} =
      Timetables.place_slot(cg, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc.id
      })

    {:ok, _student} = Academics.add_student(cg, %{full_name: "Awa Nkolo", sex: :f})
    [%{enrollment: enrollment}] = Academics.list_roster(cg)

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      school: school,
      year: year,
      cg: cg,
      tc: tc,
      period: period,
      date: date,
      head: head,
      enrollment: enrollment
    }
  end

  defp conn_for(school, user) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  test "the slot-owning teacher sees the roster and can mark a student", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    enrollment: enrollment
  } do
    {:ok, view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}")

    assert html =~ "Awa Nkolo"

    view
    |> element("#mark-#{enrollment.id}")
    |> render_change(%{"enrollment_id" => enrollment.id, "status" => "present"})

    roll = Attendance.period_roll(cg, period, date)
    assert Enum.find(roll.students, &(&1.enrollment_id == enrollment.id)).status == :present
  end

  test "a teacher who does not own the slot is redirected", %{
    school: school,
    cg: cg,
    period: period,
    date: date,
    head: head
  } do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn = conn_for(school, other)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}")
  end

  test "a conduct manager (discipline master) can mark any period", %{
    school: school,
    cg: cg,
    period: period,
    date: date,
    head: head,
    enrollment: enrollment
  } do
    dm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{
        email: to_string(dm.email),
        roles: [:discipline_master]
      })

    {:ok, _} = Schools.accept_invitation(inv.token, dm)

    conn = conn_for(school, dm)

    {:ok, view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}")

    assert html =~ "Awa Nkolo"

    view
    |> element("#mark-#{enrollment.id}")
    |> render_change(%{"enrollment_id" => enrollment.id, "status" => "absent"})

    roll = Attendance.period_roll(cg, period, date)
    assert Enum.find(roll.students, &(&1.enrollment_id == enrollment.id)).status == :absent
  end

  test "a forged enrollment_id or out-of-range status is rejected without persisting", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    enrollment: enrollment
  } do
    {:ok, view, _html} =
      live(conn, ~p"/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}")

    view
    |> element("#mark-#{enrollment.id}")
    |> render_change(%{"enrollment_id" => Ecto.UUID.generate(), "status" => "present"})

    view
    |> element("#mark-#{enrollment.id}")
    |> render_change(%{"enrollment_id" => enrollment.id, "status" => "on_fire"})

    roll = Attendance.period_roll(cg, period, date)
    assert Enum.find(roll.students, &(&1.enrollment_id == enrollment.id)).status == nil
  end

  test "a non-member is redirected to /school", %{school: school, cg: cg, period: period, date: date, head: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn = conn_for(school, other)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}")
  end

  test "cross-school class id redirects to /school/classes", %{conn: conn, period: period, date: date} do
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

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}")
  end
end
