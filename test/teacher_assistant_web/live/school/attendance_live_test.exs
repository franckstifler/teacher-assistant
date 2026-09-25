defmodule TeacherAssistantWeb.School.AttendanceLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Organization.create_school(head, %{name: "Lycée T"})
    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(cg, head, %{subject: "Maths"})

    :ok = Attendance.build_default_periods(scope)
    period = Attendance.list_periods(scope) |> Enum.find(&(&1.kind == :lesson))

    # Monday, so the slot's day_of_week matches.
    date = ~D[2025-09-08]

    {:ok, _slot} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc.id
      })

    {:ok, _student} = Enrollment.add_student(cg, %{full_name: "Awa Nkolo", sex: :f})
    [%{enrollment: enrollment}] = Enrollment.list_roster(cg)

    {:ok, profile} = Accounts.fetch_school_profile(school)
    {:ok, _} = Accounts.verify_school(profile, head.id)

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
      scope: scope,
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
    scope: scope,
    enrollment: enrollment
  } do
    {:ok, other} = Enrollment.add_student(cg, %{full_name: "Beba Ndoumbe", sex: :m})
    other_enr = Enum.find(Enrollment.list_roster(cg), &(&1.student.id == other.id)).enrollment

    {:ok, view, _html} = live(conn, att_path(cg, period, date))

    # present is the default selection for a fresh roll
    assert has_element?(view, "#att-#{enrollment.id}-present[aria-pressed='true']")

    # record without touching anyone
    view |> element("#record-roll") |> render_click()

    roll = Attendance.period_roll(scope, cg, period, date)
    assert Enum.find(roll.students, &(&1.enrollment_id == enrollment.id)).status == :present
    assert Enum.find(roll.students, &(&1.enrollment_id == other_enr.id)).status == :present
  end

  test "marking one student absent records absent for them and present for the rest", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    scope: scope,
    enrollment: enrollment
  } do
    {:ok, other} = Enrollment.add_student(cg, %{full_name: "Beba Ndoumbe", sex: :m})
    other_enr = Enum.find(Enrollment.list_roster(cg), &(&1.student.id == other.id)).enrollment

    {:ok, view, _html} = live(conn, att_path(cg, period, date))

    view |> element("#att-#{enrollment.id}-absent") |> render_click()
    view |> element("#record-roll") |> render_click()

    roll = Attendance.period_roll(scope, cg, period, date)
    assert Enum.find(roll.students, &(&1.enrollment_id == enrollment.id)).status == :absent
    assert Enum.find(roll.students, &(&1.enrollment_id == other_enr.id)).status == :present
  end

  test "a conduct manager (discipline master) can record the roll", %{
    school: school,
    cg: cg,
    period: period,
    date: date,
    head: head,
    scope: scope,
    enrollment: enrollment
  } do
    dm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{
        email: to_string(dm.email),
        roles: [:discipline_master]
      })

    {:ok, _} = Accounts.accept_invitation(inv.token, dm)

    {:ok, view, _html} = live(conn_for(school, dm), att_path(cg, period, date))

    view |> element("#att-#{enrollment.id}-absent") |> render_click()
    view |> element("#record-roll") |> render_click()

    roll = Attendance.period_roll(scope, cg, period, date)
    assert Enum.find(roll.students, &(&1.enrollment_id == enrollment.id)).status == :absent
  end

  test "the roll shows as recorded once entries exist", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    tc: tc,
    scope: scope,
    enrollment: enrollment
  } do
    {:ok, _} =
      Attendance.record_period(scope, cg, period, tc, date, [{enrollment.id, :present}])

    {:ok, view, _html} = live(conn, att_path(cg, period, date))
    assert has_element?(view, "#roll-status", "enregistré")
  end

  test "an invalid status from a forged set event is ignored", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    scope: scope,
    enrollment: enrollment
  } do
    {:ok, view, _html} = live(conn, att_path(cg, period, date))

    render_hook(view, "set", %{"enrollment_id" => enrollment.id, "status" => "on_fire"})
    view |> element("#record-roll") |> render_click()

    roll = Attendance.period_roll(scope, cg, period, date)
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
      Accounts.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, other)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn_for(school, other), att_path(cg, period, date))
  end

  describe "assignment-based roll call (no timetable slot)" do
    setup %{school: school, cg: cg, head: head, scope: scope} do
      other = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, inv} =
        Accounts.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

      {:ok, _} = Accounts.accept_invitation(inv.token, other)

      # A lesson period with no slot placed on any day.
      free_period =
        scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson)) |> Enum.at(1)

      %{other: other, free_period: free_period}
    end

    test "an assigned teacher can record the roll on a period with no slot", %{
      school: school,
      cg: cg,
      date: date,
      other: other,
      free_period: free_period,
      enrollment: enrollment
    } do
      {:ok, tc_other} = Curriculum.assign_teacher(cg, other, %{subject: "Anglais"})

      {:ok, view, _html} = live(conn_for(school, other), att_path(cg, free_period, date))
      assert has_element?(view, "#class-attendance")

      view
      |> element("#att-#{enrollment.id}-absent")
      |> render_click()

      view |> element("#record-roll") |> render_click()

      require Ash.Query

      [entry] =
        TeacherAssistant.Academics.AttendanceEntry
        |> Ash.Query.filter(enrollment_id == ^enrollment.id and period_id == ^free_period.id)
        |> Ash.read!(tenant: school.id)

      assert entry.status == :absent
      assert entry.teaching_context_id == tc_other.id
    end

    test "a colleague's placed slot beats the signed-in teacher's own assignment", %{
      school: school,
      cg: cg,
      period: period,
      date: date,
      other: other
    } do
      {:ok, _tc_other} = Curriculum.assign_teacher(cg, other, %{subject: "Anglais"})

      # `period` on `date` is the head's Maths slot (placed in the top-level setup).
      assert {:error, {:live_redirect, %{to: "/school"}}} =
               live(conn_for(school, other), att_path(cg, period, date))
    end

    test "a member with no assignment and no slot is redirected", %{
      school: school,
      cg: cg,
      date: date,
      other: other,
      free_period: free_period
    } do
      assert {:error, {:live_redirect, %{to: "/school"}}} =
               live(conn_for(school, other), att_path(cg, free_period, date))
    end
  end

  test "cross-school class id redirects to /school/classes", %{
    conn: conn,
    period: period,
    date: date
  } do
    other = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, os} = Organization.create_school(other, %{name: "Autre"})

    {:ok, oy} =
      Organization.create_academic_year(os, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} = Enrollment.create_class_group(os, oy, %{label: "6e Z", level: "6ème"})

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, att_path(ocg, period, date))
  end
end
