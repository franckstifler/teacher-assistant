defmodule TeacherAssistantWeb.School.SchoolLifeLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{
    Attendance,
    Curriculum,
    Discipline,
    Enrollment,
    Organization,
    Timetabling
  }

  # The test clock is frozen at Monday 2025-09-15, 13:00 school time.
  @today ~D[2025-09-15]

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée V"})

    scope = school_scope(head, school)
    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: e}] = Enrollment.list_roster(scope, cg)
    :ok = Attendance.build_default_periods(scope)
    [p1, p2 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    for p <- [p1, p2] do
      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: :monday,
          period_id: p.id,
          teaching_context_id: tc.id
        })
    end

    {:ok, _} = Attendance.record_period(scope, cg, p1, tc, @today, [{e.id, :absent}])

    %{
      conn: Plug.Conn.put_session(conn, :workspace_id, school.id),
      school: school,
      scope: scope,
      cg: cg,
      e: e,
      p1: p1,
      p2: p2
    }
  end

  defp conn_with_roles(school, scope, roles) do
    member = TeacherAssistant.TeacherFixtures.member_scope_fixture(scope, %{roles: roles})

    build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, member.current_user.id)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  test "Ma journée lists today's slots with their roll-call status", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/today")

    assert view |> element("#slot-#{ctx.cg.id}-#{ctx.p1.id}") |> render() =~ "Fait"
    assert view |> element("#slot-#{ctx.cg.id}-#{ctx.p1.id}") |> render() =~ "1 absent"
    assert view |> element("#slot-#{ctx.cg.id}-#{ctx.p2.id}") |> render() =~ "Non fait"
    assert has_element?(view, "#my-day h1", "Ma journée")
    assert has_element?(view, "#my-day header", "2 cours aujourd'hui")
    # the missed slot is selected on arrival, its roll call beside the list
    assert view |> element("#roll-panel") |> render() =~ ctx.p2.label
  end

  test "Ma journée records the selected slot's roll call in place", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/today?#{[slot: "#{ctx.cg.id}-#{ctx.p2.id}"]}")

    view |> element("#att-#{ctx.e.id}-late") |> render_click()
    view |> element("#record-roll") |> render_click()

    assert has_element?(view, "#record-roll", "Modifier l'appel")
    assert view |> element("#slot-#{ctx.cg.id}-#{ctx.p2.id}") |> render() =~ "Fait"
  end

  test "Ma journée sends non-teachers to their space home", ctx do
    conn = conn_with_roles(ctx.school, ctx.scope, [:bursar])
    assert {:error, {:live_redirect, %{to: "/school/classes"}}} = live(conn, ~p"/school/today")
  end

  test "Aujourd'hui: KPIs, grid, « Relancer » and recent sanctions", %{conn: conn} = ctx do
    {:ok, _} = Discipline.add_sanction(ctx.scope, ctx.e, %{type: :avertissement, date: @today})
    {:ok, view, _} = live(conn, ~p"/school/day")

    assert view |> element("#to-absences") |> render() =~ "Absences à justifier · 1"
    assert view |> element("#kpi-calls") |> render() =~ "1 / 2"
    assert view |> element("#kpi-absents") |> render() =~ "1"
    assert view |> element("#kpi-to-justify") |> render() =~ "1"

    assert has_element?(view, "#grid-#{ctx.cg.id}")
    assert view |> element("#roll-call-grid") |> render() =~ "?"
    assert has_element?(view, "#missed-#{ctx.cg.id}-#{ctx.p2.id}")
    assert view |> element("#recent-sanctions") |> render() =~ "parents à notifier"
    assert has_element?(view, "#all-sanctions[href='/school/sanctions']")

    slot =
      ctx.cg.id
      |> Timetabling.list_for_class!(scope: ctx.scope)
      |> Enum.find(&(&1.period_id == ctx.p2.id))

    view |> element("#remind-#{slot.id}") |> render_click()
    assert has_element?(view, "#reminded-#{slot.id}")
    refute has_element?(view, "#remind-#{slot.id}")
  end

  test "Absences: inline justify with a precision, then the Justifiées tab",
       %{conn: conn} = ctx do
    row_id = "#{ctx.e.id}-2025-09-15"
    {:ok, view, _} = live(conn, ~p"/school/absences")

    assert view |> element("#row-#{row_id}") |> render() =~ "Aucun contact"
    view |> element("#open-#{row_id}") |> render_click()
    view |> element("#note-#{row_id}") |> render_change(%{"note" => "Certificat médical"})
    view |> element("#justify-#{row_id}-famille") |> render_click()
    refute has_element?(view, "#row-#{row_id}")

    [entry] =
      TeacherAssistant.Academics.AttendanceEntry
      |> Ash.read!(scope: ctx.scope)
      |> Enum.filter(&(&1.status == :absent))

    assert entry.justification_note == "Certificat médical"

    {:ok, view, _} = live(conn, ~p"/school/absences?filter=justified")
    assert view |> element("#row-#{row_id}") |> render() =~ "Raison familiale"
  end

  test "Absences: class and period filters live in the URL", %{conn: conn} = ctx do
    row_id = "#{ctx.e.id}-2025-09-15"
    {:ok, view, _} = live(conn, ~p"/school/absences")

    view
    |> element("#absence-filters")
    |> render_change(%{"period" => "today", "class" => ctx.cg.id})

    assert_patch(view, ~p"/school/absences?filter=unjustified&class=#{ctx.cg.id}&period=today")
    assert has_element?(view, "#row-#{row_id}")
    assert view |> element("#absences-footer") |> render() =~ "1 sur 1"
  end

  test "Absences: the repeated-absence banner links to the student", %{conn: conn} = ctx do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(ctx.scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, %{absence_alert_hours: 1},
        scope: ctx.scope
      )
      |> Ash.update()

    # 2 periods missed: 1 h 40 unjustified, over the 1 h threshold.
    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p2, nil, @today, [{ctx.e.id, :absent}])

    {:ok, view, _} = live(conn, ~p"/school/absences")
    assert view |> element("#repeated-banner") |> render() =~ "Awa"

    assert has_element?(
             view,
             "#repeated-#{ctx.e.id}[href='/school/students/#{ctx.e.student_id}']"
           )
  end

  test "the surveillant's menu counts missed roll calls and unjustified absences", ctx do
    conn = conn_with_roles(ctx.school, ctx.scope, [:discipline_master])
    {:ok, view, _} = live(conn, ~p"/school/day")

    # p2's roll call is missed; Awa's absence at p1 is not justified
    assert view |> element("#nav-school-day .badge") |> render() =~ "1"
    assert view |> element("#nav-school-absences .badge") |> render() =~ "1"
  end

  test "school-life screens need the conduct axis", ctx do
    conn = conn_with_roles(ctx.school, ctx.scope, [:teacher])
    assert {:error, {:live_redirect, _}} = live(conn, ~p"/school/day")
    assert {:error, {:live_redirect, _}} = live(conn, ~p"/school/absences")
  end

  test "the discipline page marks parents notified", %{conn: conn} = ctx do
    {:ok, s} = Discipline.add_sanction(ctx.scope, ctx.e, %{type: :blame, date: @today})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{ctx.cg.id}/discipline")

    view |> element("#notify-parents-#{s.id}") |> render_click()
    assert view |> element("#parents-#{s.id}") |> render() =~ "Parents notifiés le 2025-09-15"
  end

  test "on a holiday both day views say so and expect no roll call (spec J1)",
       %{conn: conn} = ctx do
    year = Organization.current_academic_year(ctx.scope)

    {:ok, _} =
      Organization.create_holiday(ctx.scope, year, %{
        label: "Journée pédagogique",
        start_date: @today,
        end_date: @today
      })

    {:ok, _view, html} = live(conn, ~p"/school/day")
    assert html =~ "Jour férié : Journée pédagogique"

    {:ok, _view, html} = live(conn, ~p"/school/today")
    assert html =~ "Jour férié : Journée pédagogique"
  end

  test "Absences shows « Délai dépassé »", %{conn: conn} = ctx do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(ctx.scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, %{justification_deadline_days: 1},
        scope: ctx.scope
      )
      |> Ash.update()

    # Thursday 11 Sept: Fri 12, Sat 13 and Mon 15 are 3 lesson days later.
    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, nil, ~D[2025-09-11], [
        {ctx.e.id, :absent}
      ])

    {:ok, view, _} = live(conn, ~p"/school/absences")
    assert view |> element("#row-#{ctx.e.id}-2025-09-11") |> render() =~ "Délai dépassé"
    refute view |> element("#row-#{ctx.e.id}-2025-09-15") |> render() =~ "Délai dépassé"
  end
end
