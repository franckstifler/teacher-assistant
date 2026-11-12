defmodule TeacherAssistantWeb.School.MovedEarlierDayLiveTest do
  # The one test that moves the school clock: alone and not async, so no other
  # module sees Wednesday.
  use TeacherAssistantWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{
    Attendance,
    Curriculum,
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

  describe "roll call outside the timetable (spec 2026-11-12)" do
    # Clock: Monday 2025-09-15 13:00 WAT. The head's slots: p1 (done), p2 (missed).
    setup %{scope: scope, cg: cg, school: school} do
      lessons = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
      [_p1, _p2, p3, _p4, _p5, p6, p7 | _] = lessons
      year = Organization.current_academic_year(scope)

      teacher_conn = fn roles ->
        member = TeacherAssistant.TeacherFixtures.member_scope_fixture(scope, %{roles: roles})

        conn =
          build_conn()
          |> Phoenix.ConnTest.init_test_session(%{})
          |> put_user_in_session(member.current_user)
          |> Plug.Conn.put_session(:workspace_id, school.id)

        {conn, %{member | current_academic_year: year}}
      end

      {conn_u, scope_u} = teacher_conn.([:teacher])
      {conn_v, scope_v} = teacher_conn.([:teacher])

      {:ok, tc_u} =
        Curriculum.assign_teacher(scope, cg, scope_u.current_user, %{subject: "Anglais"})

      {:ok, tc_v} = Curriculum.assign_teacher(scope, cg, scope_v.current_user, %{subject: "SVT"})

      %{
        p3: p3,
        p6: p6,
        p7: p7,
        conn_u: conn_u,
        scope_u: scope_u,
        tc_u: tc_u,
        conn_v: conn_v,
        scope_v: scope_v,
        tc_v: tc_v
      }
    end

    defp moved_path(cg_or_course, period, date),
      do:
        ~p"/school/today?#{[class: cg_or_course, period: period.id, date: Date.to_iso8601(date)]}"

    test "an earlier day of the week is accepted at any period, without a vacated slot offer",
         %{conn: conn} = ctx do
      previous = Application.get_env(:teacher_assistant, :school_clock_now)
      Application.put_env(:teacher_assistant, :school_clock_now, ~U[2025-09-17 12:00:00Z])
      on_exit(fn -> Application.put_env(:teacher_assistant, :school_clock_now, previous) end)

      tuesday = ~D[2025-09-16]
      {:ok, view, _} = live(conn, moved_path(ctx.cg.id, ctx.p7, tuesday))
      assert view |> element("#roll-panel") |> render() =~ "Appel · "
      refute has_element?(view, "#moved-from")

      view |> element("#record-roll") |> render_click()
      assert has_element?(view, "#roll-panel", "Appel enregistré")

      assert [%{moved?: true}] =
               Attendance.teacher_day(
                 ctx.scope,
                 ctx.scope.current_user,
                 tuesday,
                 ~N[2025-09-17 13:00:00]
               )
    end
  end
end
