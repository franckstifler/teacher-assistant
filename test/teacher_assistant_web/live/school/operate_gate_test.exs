defmodule TeacherAssistantWeb.School.OperateGateTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée G",
        school_type: :lycee,
        subsystem: :francophone,
        sector: :public,
        region: :centre,
        town: "Yaoundé"
      })

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

    {:ok, _slot} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc.id
      })

    {:ok, _student} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      school: school,
      cg: cg,
      period: period,
      date: ~D[2025-09-08],
      head: head,
      scope: scope
    }
  end

  test "an unverified school cannot record attendance", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    scope: scope
  } do
    {:ok, view, _} =
      live(conn, "/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}")

    view |> element("#record-roll") |> render_click()
    roll = Attendance.period_roll(scope, cg, period, date)
    assert Enum.all?(roll.students, &(&1.status == nil))
  end

  test "a verified school can record attendance", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date,
    head: head,
    scope: scope
  } do
    {:ok, p} = Accounts.fetch_school_profile(scope)
    {:ok, _} = Accounts.verify_school(p, head.id, scope: scope)

    {:ok, view, _} =
      live(conn, "/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}")

    view |> element("#record-roll") |> render_click()
    roll = Attendance.period_roll(scope, cg, period, date)
    assert Enum.any?(roll.students, &(&1.status == :present))
  end
end
