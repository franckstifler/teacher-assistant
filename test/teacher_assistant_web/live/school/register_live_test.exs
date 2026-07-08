defmodule TeacherAssistantWeb.School.RegisterLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Attendance
  alias TeacherAssistant.Academics.Timetables
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

    {:ok, _count} =
      Attendance.record_period(cg, period, tc, date, [{enrollment.id, :absent}], head.id)

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

  test "a conduct manager (discipline master) sees the grid and can justify a student's day", %{
    school: school,
    cg: cg,
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
      live(conn, ~p"/school/classes/#{cg.id}/register?date=#{Date.to_iso8601(date)}")

    assert html =~ "Awa Nkolo"
    assert has_element?(view, "#justify-#{enrollment.id}")

    view
    |> form("#justify-form-#{enrollment.id}", %{"note" => "Certificat médical"})
    |> render_submit()

    conduct = Attendance.student_conduct(enrollment, {:sequence, Academics.current_sequence(TeacherAssistant.Academics.current_academic_year(school), date)})
    assert Decimal.compare(conduct.justified_hours, Decimal.new(0)) == :gt
    assert Decimal.compare(conduct.unjustified_hours, Decimal.new(0)) == :eq
  end

  test "the date picker reloads a different day's grid", %{
    conn: conn,
    cg: cg,
    head: head,
    date: date
  } do
    other_date = Date.add(date, 7)
    {:ok, _student2} = Academics.add_student(cg, %{full_name: "Zinedine Bello", sex: :m})
    _ = head

    {:ok, view, html} = live(conn, ~p"/school/classes/#{cg.id}/register?date=#{Date.to_iso8601(date)}")
    assert html =~ Date.to_string(date)

    html =
      view
      |> form("#register-date-form", %{"date" => Date.to_iso8601(other_date)})
      |> render_submit()

    assert html =~ Date.to_string(other_date)
  end

  test "a form master sees the grid read-only and a forged justify event is rejected", %{
    school: school,
    cg: cg,
    date: date,
    head: head,
    enrollment: enrollment
  } do
    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(fm.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, fm)
    {:ok, _} = Academics.set_form_master(cg, fm.id)

    conn = conn_for(school, fm)

    {:ok, view, html} =
      live(conn, ~p"/school/classes/#{cg.id}/register?date=#{Date.to_iso8601(date)}")

    assert html =~ "Awa Nkolo"
    refute has_element?(view, "#justify-form-#{enrollment.id}")

    view
    |> render_hook("justify", %{"enrollment_id" => enrollment.id, "note" => "forged"})

    conduct =
      Attendance.student_conduct(
        enrollment,
        {:sequence, Academics.current_sequence(Academics.current_academic_year(school), date)}
      )

    assert Decimal.compare(conduct.justified_hours, Decimal.new(0)) == :eq
  end

  test "a plain teacher who is not the form master is redirected to /school", %{
    school: school,
    cg: cg,
    date: date,
    head: head
  } do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn = conn_for(school, other)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}/register?date=#{Date.to_iso8601(date)}")
  end

  test "cross-school class id redirects to /school/classes", %{conn: conn, date: date} do
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
             live(conn, ~p"/school/classes/#{ocg.id}/register?date=#{Date.to_iso8601(date)}")
  end
end
