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

  defp att_path(cg, period, date),
    do: "/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}"

  test "every student defaults to present, and recording writes present for all", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    enrollment: enrollment
  } do
    {:ok, other} = Academics.add_student(cg, %{full_name: "Beba Ndoumbe", sex: :m})
    other_enr = Enum.find(Academics.list_roster(cg), &(&1.student.id == other.id)).enrollment

    {:ok, view, _html} = live(conn, att_path(cg, period, date))

    # present is the default selection for a fresh roll
    assert has_element?(view, "#att-#{enrollment.id}-present[aria-pressed='true']")

    # record without touching anyone
    view |> element("#record-roll") |> render_click()

    roll = Attendance.period_roll(cg, period, date)
    assert Enum.find(roll.students, &(&1.enrollment_id == enrollment.id)).status == :present
    assert Enum.find(roll.students, &(&1.enrollment_id == other_enr.id)).status == :present
  end

  test "marking one student absent records absent for them and present for the rest", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    enrollment: enrollment
  } do
    {:ok, other} = Academics.add_student(cg, %{full_name: "Beba Ndoumbe", sex: :m})
    other_enr = Enum.find(Academics.list_roster(cg), &(&1.student.id == other.id)).enrollment

    {:ok, view, _html} = live(conn, att_path(cg, period, date))

    view |> element("#att-#{enrollment.id}-absent") |> render_click()
    view |> element("#record-roll") |> render_click()

    roll = Attendance.period_roll(cg, period, date)
    assert Enum.find(roll.students, &(&1.enrollment_id == enrollment.id)).status == :absent
    assert Enum.find(roll.students, &(&1.enrollment_id == other_enr.id)).status == :present
  end

  test "a conduct manager (discipline master) can record the roll", %{
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

    {:ok, view, _html} = live(conn_for(school, dm), att_path(cg, period, date))

    view |> element("#att-#{enrollment.id}-absent") |> render_click()
    view |> element("#record-roll") |> render_click()

    roll = Attendance.period_roll(cg, period, date)
    assert Enum.find(roll.students, &(&1.enrollment_id == enrollment.id)).status == :absent
  end

  test "the roll shows as recorded once entries exist", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    tc: tc,
    head: head,
    enrollment: enrollment
  } do
    {:ok, _} =
      Attendance.record_period(cg, period, tc, date, [{enrollment.id, :present}], head.id)

    {:ok, view, _html} = live(conn, att_path(cg, period, date))
    assert has_element?(view, "#roll-status", "enregistré")
  end

  test "an invalid status from a forged set event is ignored", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    enrollment: enrollment
  } do
    {:ok, view, _html} = live(conn, att_path(cg, period, date))

    render_hook(view, "set", %{"enrollment_id" => enrollment.id, "status" => "on_fire"})
    view |> element("#record-roll") |> render_click()

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

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn_for(school, other), att_path(cg, period, date))
  end

  test "cross-school class id redirects to /school/classes", %{
    conn: conn,
    period: period,
    date: date
  } do
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
             live(conn, att_path(ocg, period, date))
  end
end
