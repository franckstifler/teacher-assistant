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
    # The app roll call rule; paper classes are covered in school_life_test.exs.
    {:ok, cg} = Enrollment.set_paper_roll_call(scope, cg, false)
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
    |> put_user_in_session(member.current_user)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  test "Ma journée lists today's slots with their roll-call status", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/today")

    assert view |> element("#slot-#{ctx.cg.id}-#{ctx.p1.id}") |> render() =~ "Appel fait"
    assert view |> element("#slot-#{ctx.cg.id}-#{ctx.p1.id}") |> render() =~ "1 absent"
    assert view |> element("#slot-#{ctx.cg.id}-#{ctx.p1.id}") |> render() =~ "1 élève"
    assert view |> element("#slot-#{ctx.cg.id}-#{ctx.p2.id}") |> render() =~ "Non fait"
    assert has_element?(view, "#my-day h1", "Bonjour")
    assert has_element?(view, "#today-slots h2", "Aujourd'hui")
    assert has_element?(view, "#my-day header", "2 cours aujourd'hui")
    # a break between two lessons is a thin separator — none between p1 and p2
    refute has_element?(view, "#today-slots", "Récréation")
    # nothing under way at 13:00 and nothing left: the hero is the missed lesson,
    # its roll call closed until « Faire l'appel »
    assert has_element?(view, "#now-card", "Appel non fait")
    assert has_element?(view, "#now-card", "Maths · 6e A")
    assert has_element?(view, "#now-marks[href^='/teacher/contexts/']")
    refute has_element?(view, "#roll-panel")

    view |> element("#now-call") |> render_click()
    assert_patch(view, ~p"/school/today?#{[slot: "#{ctx.cg.id}-#{ctx.p2.id}"]}")
    assert view |> element("#roll-panel") |> render() =~ ctx.p2.label
    refute has_element?(view, "#now-card")
    assert has_element?(view, "#slot-#{ctx.cg.id}-#{ctx.p2.id}[aria-current='true']")

    view |> element("#close-roll") |> render_click()
    assert_patch(view, ~p"/school/today")
    refute has_element?(view, "#roll-panel")
  end

  test "Ma journée: the hero is the lesson under way, a roll call opens from the timeline",
       %{conn: conn} = ctx do
    # a third lesson, 13:30–14:20 on Monday: the next one at 13:00
    [_, _, _, _, _, _, p7 | _] =
      ctx.scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    tc = ctx.cg.id |> Timetabling.list_for_class!(scope: ctx.scope) |> hd()

    {:ok, _} =
      Timetabling.place_slot(ctx.scope, ctx.cg, %{
        day: :monday,
        period_id: p7.id,
        teaching_context_id: tc.teaching_context_id
      })

    {:ok, view, _} = live(conn, ~p"/school/today")
    assert has_element?(view, "#now-card", "Prochain cours")
    assert has_element?(view, "#now-state", "L'appel s'ouvrira à 13:30")
    refute has_element?(view, "#now-call")
    # the lunch break sits between p2 and p7; upcoming lessons are not links
    assert has_element?(view, "#today-slots", "Pause")
    refute has_element?(view, "a#slot-#{ctx.cg.id}-#{p7.id}")

    view |> element("#slot-#{ctx.cg.id}-#{ctx.p1.id}") |> render_click()
    assert has_element?(view, "#record-roll", "Modifier l'appel")
    assert has_element?(view, "#roll-footer", "Appel enregistré")
  end

  test "Ma journée records the selected slot's roll call in place", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/today?#{[slot: "#{ctx.cg.id}-#{ctx.p2.id}"]}")

    assert has_element?(view, "#record-roll", "Valider l'appel · 0 absent, 0 retard")
    view |> element("#att-#{ctx.e.id}-late") |> render_click()
    assert has_element?(view, "#record-roll", "Valider l'appel · 0 absent, 1 retard")
    view |> element("#record-roll") |> render_click()

    assert has_element?(view, "#record-roll", "Modifier l'appel")
    assert view |> element("#slot-#{ctx.cg.id}-#{ctx.p2.id}") |> render() =~ "Appel fait"
  end

  test "Ma journée: a combined course is one lesson, its next period « mêmes classes »",
       %{conn: conn} = ctx do
    {:ok, cg_b} =
      Enrollment.create_class_group(ctx.scope, Organization.current_academic_year(ctx.scope), %{
        label: "6e B",
        level: "6ème"
      })

    {:ok, cg_b} = Enrollment.set_paper_roll_call(ctx.scope, cg_b, false)
    {:ok, _} = Enrollment.add_student(ctx.scope, cg_b, %{full_name: "Bello", sex: :m})
    tc = ctx.cg.id |> Timetabling.list_for_class!(scope: ctx.scope) |> hd()

    tc =
      Ash.get!(TeacherAssistant.Academics.TeachingContext, tc.teaching_context_id,
        scope: ctx.scope
      )

    head = ctx.scope.current_user
    {:ok, tc_b} = Curriculum.assign_teacher(ctx.scope, cg_b, head, %{subject: "Maths"})
    {:ok, course} = Curriculum.combine_course(ctx.scope, [tc, tc_b])

    for p <- [ctx.p1, ctx.p2] do
      {:ok, _} =
        Timetabling.place_slot(ctx.scope, cg_b, %{
          day: :monday,
          period_id: p.id,
          teaching_context_id: tc_b.id
        })
    end

    {:ok, view, _} = live(conn, ~p"/school/today")

    first = view |> element("#slot-#{ctx.cg.id}-#{ctx.p1.id}") |> render()
    assert first =~ course.label
    assert first =~ "2 classes · 2 élèves"
    refute has_element?(view, "#slot-#{cg_b.id}-#{ctx.p1.id}")

    assert view |> element("#slot-#{ctx.cg.id}-#{ctx.p2.id}") |> render() =~
             "mêmes classes · 2e heure"

    assert has_element?(view, "#my-day header", "2 cours aujourd'hui")
  end

  test "Ma journée: « À faire » counts the séquence's courses without an evaluation",
       %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/today")

    assert has_element?(
             view,
             "#todo-marks[href='/school/courses?f=marks']",
             "1 cours sans évaluation"
           )

    assert has_element?(view, "#sequence-panel", "Créer une évaluation")
  end

  test "Ma journée sends non-teachers to their space home", ctx do
    conn = conn_with_roles(ctx.school, ctx.scope, [:bursar])
    assert {:error, {:live_redirect, %{to: "/school/fees"}}} = live(conn, ~p"/school/today")
  end

  test "Aujourd'hui: KPIs, grid, « Relancer » and recent sanctions", %{conn: conn} = ctx do
    {:ok, _} = Discipline.add_sanction(ctx.scope, ctx.e, %{type: :avertissement, date: @today})
    {:ok, view, _} = live(conn, ~p"/school/day")

    assert view |> element("#to-absences") |> render() =~ "Absences à justifier · 1"
    assert view |> element("#kpi-calls") |> render() =~ "1 / 2"
    assert view |> element("#kpi-absents") |> render() =~ "1"
    assert view |> element("#kpi-to-justify") |> render() =~ "1"

    assert has_element?(view, "#calls-summary", "1 appel manquant aujourd'hui")
    assert has_element?(view, "#grid-#{ctx.cg.id}")
    # p1 done (1 absent, success), p2 finished without a roll call (error)
    grid = view |> element("#roll-call-grid") |> render()
    assert grid =~ "!"
    assert grid =~ "bg-error/15"
    assert grid =~ "bg-success/12"

    assert has_element?(
             view,
             "#roll-call-grid a[href='/school/classes/#{ctx.cg.id}/attendance/#{ctx.p2.id}?date=2025-09-15']"
           )

    # phone: the lessons of the day, each with its state, opening onto its classes
    assert has_element?(view, "#period-hero")
    assert has_element?(view, "#period-#{ctx.p1.id}", "1/1 · 1 abs.")
    assert has_element?(view, "#period-#{ctx.p2.id}", "0/1 à jour")

    assert has_element?(
             view,
             "#period-#{ctx.p2.id} a[href='/school/classes/#{ctx.cg.id}/attendance/#{ctx.p2.id}?date=2025-09-15']",
             "Appel non fait"
           )

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

  describe "paper roll call (spec 2026-10-28)" do
    setup %{scope: scope, cg: cg} do
      {:ok, cg} = Enrollment.set_paper_roll_call(scope, cg, true)
      %{cg: cg}
    end

    test "Aujourd'hui: an untaken paper lesson waits « sur feuille », not missed",
         %{conn: conn} = ctx do
      {:ok, view, _} = live(conn, ~p"/school/day")

      refute has_element?(view, "#missed-#{ctx.cg.id}-#{ctx.p2.id}")
      assert has_element?(view, "#paper-#{ctx.cg.id}-#{ctx.p2.id}", "sur feuille · à saisir")
      assert has_element?(view, "#paper-#{ctx.cg.id}-#{ctx.p2.id} button", "Relancer")
      assert has_element?(view, "#grid-legend", "Sur feuille")
      assert has_element?(view, "#grid-legend", "Non assuré")
      assert has_element?(view, "#kpi-calls", "1 sur feuille")
      assert has_element?(view, "#calls-summary", "1 appel sur feuille, à saisir")
      assert has_element?(view, ~s(#print-all-sheets[href="/school/roll-sheets/print"]))

      # phone: a paper lesson opens the class's roll sheet
      assert has_element?(
               view,
               ~s(#period-#{ctx.p2.id} a[href="/school/classes/#{ctx.cg.id}/roll-sheet"]),
               "Sur feuille"
             )

      assert has_element?(
               view,
               ~s(#grid-#{ctx.cg.id} a[href="/school/classes/#{ctx.cg.id}/roll-sheet"])
             )

      view |> element("#paper-#{ctx.cg.id}-#{ctx.p2.id} button", "Relancer") |> render_click()
      assert render(view) =~ "Relancé ✓"
    end

    test "the dashboard counts app and paper roll calls apart", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/school")
      assert has_element?(view, "#kpi-calls", "1 appel dans l'app · 1 sur feuille")

      assert has_element?(
               view,
               "#todo-paper a[href='/school/day']",
               "1 appel sur feuille à reporter"
             )
    end

    test "Ma journée: a paper lesson is not a red « non fait »", %{conn: conn} = ctx do
      {:ok, view, _} = live(conn, ~p"/school/today")
      slot = view |> element("#slot-#{ctx.cg.id}-#{ctx.p2.id}") |> render()

      refute slot =~ "Non fait"
      assert slot =~ "Sur feuille"
    end

    test "the register switches paper roll call; a teacher sees no switch", %{conn: conn} = ctx do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{ctx.cg.id}/register")
      view |> element("#paper-roll-call-toggle") |> render_click()

      {:ok, cg} = Enrollment.fetch_owned_class_group(ctx.scope, ctx.cg.id)
      refute cg.paper_roll_call

      teacher_conn = conn_with_roles(ctx.school, ctx.scope, [:teacher])

      case live(teacher_conn, ~p"/school/classes/#{ctx.cg.id}/register") do
        {:ok, view, _} -> refute has_element?(view, "#paper-roll-call-toggle")
        {:error, _redirect} -> :ok
      end
    end

    test "the settings switch every class off at once", %{conn: conn} = ctx do
      {:ok, view, _} = live(conn, ~p"/school/settings/school-life")

      assert view |> element("#paper-all-off") |> render_click() =~ "Réglage enregistré."

      {:ok, cg} = Enrollment.fetch_owned_class_group(ctx.scope, ctx.cg.id)
      refute cg.paper_roll_call
    end
  end
end
