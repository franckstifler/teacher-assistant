defmodule TeacherAssistantWeb.School.RegisterLiveTest do
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
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée R"})

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

    {:ok, _count} =
      Attendance.record_period(scope, cg, period, tc, date, [{enrollment.id, :absent}])

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

  test "a conduct manager (discipline master) sees the grid and can justify a student's day", %{
    school: school,
    cg: cg,
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

    conn = conn_for(school, dm)

    {:ok, view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/register?date=#{Date.to_iso8601(date)}")

    assert html =~ "Awa Nkolo"
    refute has_element?(view, "#student-day-drawer")
    view |> element("#open-student-#{enrollment.id}") |> render_click()
    assert has_element?(view, "#student-day-drawer", "Awa Nkolo")
    assert has_element?(view, "#justify-#{enrollment.id}")

    view
    |> form("#justify-form-#{enrollment.id}", %{
      "reason" => "maladie",
      "note" => "Certificat médical"
    })
    |> render_submit()

    refute has_element?(view, "#student-day-drawer")

    conduct =
      Attendance.student_conduct(
        scope,
        enrollment,
        {:sequence,
         Organization.current_sequence(
           scope,
           TeacherAssistant.Organization.current_academic_year(scope),
           date
         )}
      )

    assert Decimal.compare(conduct.justified_hours, Decimal.new(0)) == :gt
    assert Decimal.compare(conduct.unjustified_hours, Decimal.new(0)) == :eq

    # the phone row opens the same drawer, and the day can be un-justified
    view |> element("#register-item-#{enrollment.id}") |> render_click()
    view |> element("#unjustify-#{enrollment.id}") |> render_click()

    conduct =
      Attendance.student_conduct(
        scope,
        enrollment,
        {:sequence,
         Organization.current_sequence(scope, Organization.current_academic_year(scope), date)}
      )

    assert Decimal.compare(conduct.justified_hours, Decimal.new(0)) == :eq
  end

  test "absence hours render rounded with a decimal comma, never a long decimal", %{
    conn: conn,
    cg: cg,
    date: date
  } do
    {:ok, _view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/register?date=#{Date.to_iso8601(date)}")

    # 50-minute period absence = 50/60 h; must display as 0,83 h, never 0.8333…
    refute html =~ "0.83"
    refute html =~ "0,8333"
    assert html =~ "0,83 h"
  end

  test "each period shows a mark, in the grid and in the phone row", %{
    conn: conn,
    cg: cg,
    date: date,
    period: period,
    enrollment: enrollment
  } do
    {:ok, view, _html} =
      live(conn, ~p"/school/classes/#{cg.id}/register?date=#{Date.to_iso8601(date)}")

    assert has_element?(view, "#cell-#{enrollment.id}-#{period.id} .text-error", "A")
    assert has_element?(view, "#register-item-#{enrollment.id} .text-error", "A")
    assert has_element?(view, "#register-item-#{enrollment.id}", "Pas d'appel")
  end

  # Fees 2: a lesson missed because the student was sent home for fees is not an absence.
  test "a sent-home mark shows RF, not an absence", %{
    conn: conn,
    cg: cg,
    date: date,
    period: period,
    tc: tc,
    scope: scope,
    enrollment: enrollment
  } do
    {:ok, _} = TeacherAssistant.FeeControl.record_send_out(scope, enrollment, date)

    {:ok, 1} =
      Attendance.record_period(scope, cg, period, tc, date, [{enrollment.id, :sent_home}])

    {:ok, view, _html} =
      live(conn, ~p"/school/classes/#{cg.id}/register?date=#{Date.to_iso8601(date)}")

    assert has_element?(view, "#cell-#{enrollment.id}-#{period.id} .text-info", "RF")
    refute has_element?(view, "#cell-#{enrollment.id}-#{period.id} .text-error")
  end

  test "the date picker reloads a different day's grid", %{
    conn: conn,
    cg: cg,
    head: head,
    date: date,
    scope: scope
  } do
    other_date = Date.add(date, 7)
    {:ok, _student2} = Enrollment.add_student(scope, cg, %{full_name: "Zinedine Bello", sex: :m})
    _ = head

    {:ok, view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/register?date=#{Date.to_iso8601(date)}")

    # the day in words, never in ISO
    assert html =~ "lundi 8 septembre"
    refute html =~ Date.to_string(date) <> "<"

    view
    |> form("#register-date-form", %{"date" => Date.to_iso8601(other_date)})
    |> render_change()

    assert_patch(view, ~p"/school/classes/#{cg.id}/register?date=#{Date.to_iso8601(other_date)}")
    assert has_element?(view, "#register-date", "lundi 15 septembre")

    view |> element("#register-prev-day") |> render_click()
    assert has_element?(view, "#register-date", "dimanche 14 septembre")

    view |> element("#register-next-day") |> render_click()
    view |> element("#register-next-day") |> render_click()
    assert has_element?(view, "#register-date", "mardi 16 septembre")
  end

  test "a form master sees the grid read-only and a forged justify event is rejected", %{
    school: school,
    cg: cg,
    date: date,
    scope: scope,
    enrollment: enrollment
  } do
    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(scope, %{email: to_string(fm.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: fm}, inv.token)
    {:ok, _} = Enrollment.set_form_master(scope, cg, fm.id)

    conn = conn_for(school, fm)

    {:ok, view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/register?date=#{Date.to_iso8601(date)}")

    assert html =~ "Awa Nkolo"
    refute has_element?(view, "#open-student-#{enrollment.id}")
    refute has_element?(view, "button#register-item-#{enrollment.id}")
    render_hook(view, "open_student", %{"id" => enrollment.id})
    refute has_element?(view, "#student-day-drawer")
    refute has_element?(view, "#justify-form-#{enrollment.id}")

    view
    |> render_hook("justify", %{"enrollment_id" => enrollment.id, "note" => "forged"})

    conduct =
      Attendance.student_conduct(
        scope,
        enrollment,
        {:sequence,
         Organization.current_sequence(scope, Organization.current_academic_year(scope), date)}
      )

    assert Decimal.compare(conduct.justified_hours, Decimal.new(0)) == :eq
  end

  test "a plain teacher who is not the form master is redirected to /school", %{
    school: school,
    cg: cg,
    date: date,
    scope: scope
  } do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(scope, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

    conn = conn_for(school, other)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}/register?date=#{Date.to_iso8601(date)}")
  end

  test "cross-school class id redirects to /school/classes", %{conn: conn, date: date} do
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
             live(conn, ~p"/school/classes/#{ocg.id}/register?date=#{Date.to_iso8601(date)}")
  end
end
