defmodule TeacherAssistantWeb.School.OperateGateTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{Assignments, Attendance, Timetables}
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Schools.create_school(head, %{
        name: "Lycée G",
        school_type: :lycee,
        subsystem: :francophone,
        sector: :public,
        region: :centre,
        town: "Yaoundé"
      })

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

    {:ok, _slot} =
      Timetables.place_slot(cg, %{day: :monday, period_id: period.id, teaching_context_id: tc.id})

    {:ok, _student} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, period: period, date: ~D[2025-09-08], head: head}
  end

  test "an unverified school cannot record attendance", %{
    conn: conn,
    cg: cg,
    period: period,
    date: date
  } do
    {:ok, view, _} =
      live(conn, "/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}")

    view |> element("#record-roll") |> render_click()
    roll = Attendance.period_roll(cg, period, date)
    assert Enum.all?(roll.students, &(&1.status == nil))
  end

  test "a verified school can record attendance", %{
    conn: conn,
    school: school,
    cg: cg,
    period: period,
    date: date,
    head: head
  } do
    {:ok, p} = Schools.fetch_school_profile(school)
    {:ok, _} = Schools.verify_school(p, head.id)

    {:ok, view, _} =
      live(conn, "/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}")

    view |> element("#record-roll") |> render_click()
    roll = Attendance.period_roll(cg, period, date)
    assert Enum.any?(roll.students, &(&1.status == :present))
  end
end
