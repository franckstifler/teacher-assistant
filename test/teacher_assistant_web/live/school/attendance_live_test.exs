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
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée T"})

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

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

    {:ok, _student} = Enrollment.add_student(scope, cg, %{full_name: "Awa Nkolo", sex: :f})
    [%{enrollment: enrollment}] = Enrollment.list_roster(scope, cg)

    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)

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
    |> put_user_in_session(user)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  defp att_path(cg, period, date),
    do: "/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}"

  test "the second hour opens prefilled from the first: absences, not lates", ctx do
    %{conn: conn, cg: cg, period: p1, date: date, scope: scope, tc: tc} = ctx
    lessons = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    p2 = Enum.at(lessons, 1)

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p2.id,
        teaching_context_id: tc.id
      })

    {:ok, late} = Enrollment.add_student(scope, cg, %{full_name: "Beba Ndoumbe", sex: :m})

    late_enr =
      Enum.find(Enrollment.list_roster(scope, cg), &(&1.student.id == late.id)).enrollment

    {:ok, 2} =
      Attendance.record_period(scope, cg, p1, tc, date, [
        {ctx.enrollment.id, :absent},
        {late_enr.id, :late, 5}
      ])

    {:ok, view, _html} = live(conn, att_path(cg, p2, date))

    assert has_element?(view, "#roll-prefilled", "heure précédente")
    assert has_element?(view, "#student-row-#{ctx.enrollment.id}[data-status='absent']")
    assert has_element?(view, "#student-row-#{late_enr.id}[data-status='present']")
    assert has_element?(view, "#roll-counts", "1 absent")
    assert has_element?(view, "#roll-counts", "0 retard")
    # not taken yet
    assert has_element?(view, "#record-roll", "Valider l'appel")
    refute has_element?(view, "#roll-footer", "Appel enregistré")
    # no « aussi pour la 2e heure » box on this page
    refute has_element?(view, "#record-following")
  end

  test "the roll-call page never writes the following hour", ctx do
    %{conn: conn, cg: cg, period: p1, date: date, scope: scope, tc: tc} = ctx
    lessons = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    p2 = Enum.at(lessons, 1)

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p2.id,
        teaching_context_id: tc.id
      })

    {:ok, view, _html} = live(conn, att_path(cg, p1, date))
    view |> element("#att-#{ctx.enrollment.id}-late") |> render_click()
    view |> element("#record-roll") |> render_click()

    refute has_element?(view, "#roll-footer", "pour 2 heures")
    %{students: [s]} = Attendance.period_roll(scope, cg, p2, date)
    assert s.status == nil
  end

  test "a student sent home after the first hour opens the second as sent home", ctx do
    %{conn: conn, cg: cg, period: p1, date: date, scope: scope, tc: tc} = ctx
    lessons = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    p2 = Enum.at(lessons, 1)

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p2.id,
        teaching_context_id: tc.id
      })

    {:ok, 1} = Attendance.record_period(scope, cg, p1, tc, date, [{ctx.enrollment.id, :present}])
    {:ok, _} = TeacherAssistant.FeeControl.record_send_out(scope, ctx.enrollment, date)

    {:ok, view, _html} = live(conn, att_path(cg, p2, date))
    assert has_element?(view, "#roll-prefilled")
    assert has_element?(view, "#student-row-#{ctx.enrollment.id}[data-status='sent_home']")
  end

  test "every student defaults to present, and recording writes present for all", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    scope: scope,
    enrollment: enrollment
  } do
    {:ok, other} = Enrollment.add_student(scope, cg, %{full_name: "Beba Ndoumbe", sex: :m})

    other_enr =
      Enum.find(Enrollment.list_roster(scope, cg), &(&1.student.id == other.id)).enrollment

    {:ok, view, _html} = live(conn, att_path(cg, period, date))

    # present is the default for a fresh roll: neither toggle is on
    assert has_element?(view, "#student-row-#{enrollment.id}[data-status='present']")
    assert has_element?(view, "#att-#{enrollment.id}-absent[aria-pressed='false']")
    assert has_element?(view, "#roll-help", "présent par défaut")

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
    {:ok, other} = Enrollment.add_student(scope, cg, %{full_name: "Beba Ndoumbe", sex: :m})

    other_enr =
      Enum.find(Enrollment.list_roster(scope, cg), &(&1.student.id == other.id)).enrollment

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
    scope: scope,
    enrollment: enrollment
  } do
    dm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(scope, %{
        email: to_string(dm.email),
        roles: [:discipline_master]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: dm}, inv.token)

    {:ok, view, _html} = live(conn_for(school, dm), att_path(cg, period, date))

    # the surveillant's way back is their own « Aujourd'hui », lit in the menu
    assert has_element?(view, ~s(#back-header-arrow[href="/school/day"]))
    assert has_element?(view, ~s(#back-header-parent[href="/school/day"]))
    assert has_element?(view, "#nav-school-day[aria-current=page]")

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
    assert has_element?(view, "#record-roll", "Modifier l'appel")
    assert has_element?(view, "#roll-footer", "Appel enregistré")
  end

  test "the record footer rides above the phone tab bar", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date
  } do
    {:ok, view, _html} = live(conn, att_path(cg, period, date))
    assert has_element?(view, "#roll-footer.ta-stickyfoot")
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
    scope: scope
  } do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(scope, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn_for(school, other), att_path(cg, period, date))
  end

  describe "assignment-based roll call (no timetable slot)" do
    setup %{scope: scope} do
      other = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, inv} =
        Accounts.invite_member(scope, %{email: to_string(other.email), roles: [:teacher]})

      {:ok, _} =
        Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

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
      enrollment: enrollment,
      scope: scope
    } do
      {:ok, tc_other} = Curriculum.assign_teacher(scope, cg, other, %{subject: "Anglais"})

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
        |> Ash.read!(scope: scope)

      assert entry.status == :absent
      assert entry.teaching_context_id == tc_other.id
    end

    test "a colleague's placed slot beats the signed-in teacher's own assignment", %{
      school: school,
      cg: cg,
      period: period,
      date: date,
      other: other,
      scope: scope
    } do
      {:ok, _tc_other} = Curriculum.assign_teacher(scope, cg, other, %{subject: "Anglais"})

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

    {:ok, os} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: other}, %{name: "Autre"})

    other_scope = school_scope(other, os)

    {:ok, oy} =
      Organization.create_academic_year(other_scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} = Enrollment.create_class_group(other_scope, oy, %{label: "6e Z", level: "6ème"})

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, att_path(ocg, period, date))
  end

  test "a late can carry minutes, saved with the roll call", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    scope: scope,
    enrollment: enrollment
  } do
    {:ok, view, _} = live(conn, att_path(cg, period, date))
    refute has_element?(view, "#late-minutes-#{enrollment.id}")

    view |> element("#att-#{enrollment.id}-late") |> render_click()
    assert has_element?(view, "#late-minutes-#{enrollment.id}")

    view
    |> form("#late-minutes-form-#{enrollment.id}", %{"minutes" => %{enrollment.id => "25"}})
    |> render_change()

    view |> element("#record-roll") |> render_click()

    %{students: [%{status: :late, late_minutes: 25}]} =
      Attendance.period_roll(scope, cg, period, date)
  end

  test "« Tous présents » resets absents and lates", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    scope: scope,
    enrollment: e1
  } do
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bello Nana", sex: :m})

    e2 =
      scope
      |> Enrollment.list_roster(cg)
      |> Enum.map(& &1.enrollment)
      |> Enum.find(&(&1.id != e1.id))

    {:ok, view, _html} = live(conn, att_path(cg, period, date))
    view |> element("#att-#{e1.id}-absent") |> render_click()
    view |> element("#att-#{e2.id}-late") |> render_click()
    assert has_element?(view, "#late-minutes-#{e2.id}")

    view |> element("#all-present") |> render_click()
    assert has_element?(view, "#student-row-#{e1.id}[data-status='present']")
    refute has_element?(view, "#late-minutes-#{e2.id}")
    assert has_element?(view, "#roll-counts", "0 absent")
  end

  test "before recording the button reads « Valider l'appel », after « Modifier l'appel »", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date
  } do
    {:ok, view, _html} = live(conn, att_path(cg, period, date))
    assert has_element?(view, "#record-roll", "Valider l'appel")
    view |> element("#record-roll") |> render_click()
    assert has_element?(view, "#record-roll", "Modifier l'appel")
  end

  test "tapping an active toggle puts the student back to present", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    enrollment: e
  } do
    {:ok, view, _html} = live(conn, att_path(cg, period, date))
    assert has_element?(view, "#class-attendance h1", "Appel · ")

    view |> element("#att-#{e.id}-absent") |> render_click()
    assert has_element?(view, "#student-row-#{e.id}[data-status='absent']")
    assert has_element?(view, "#att-#{e.id}-absent[aria-pressed='true']")
    assert has_element?(view, "#roll-counts", "1 absent")

    view |> element("#att-#{e.id}-absent") |> render_click()
    assert has_element?(view, "#student-row-#{e.id}[data-status='present']")

    view |> element("#att-#{e.id}-late") |> render_click()
    assert has_element?(view, "#late-minutes-#{e.id}")
    view |> element("#att-#{e.id}-absent") |> render_click()
    assert has_element?(view, "#student-row-#{e.id}[data-status='absent']")
    refute has_element?(view, "#late-minutes-#{e.id}")
  end
end
