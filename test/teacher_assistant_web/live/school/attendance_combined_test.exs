defmodule TeacherAssistantWeb.School.AttendanceCombinedTest do
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
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Combiné"
      })

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, maco} =
      Enrollment.create_class_group(scope, year, %{label: "1ère MACO", level: "1ère"})

    {:ok, menu} =
      Enrollment.create_class_group(scope, year, %{label: "1ère MENU", level: "1ère"})

    {:ok, tc_maco} = Curriculum.assign_teacher(scope, maco, head, %{subject: "Maths"})
    {:ok, tc_menu} = Curriculum.assign_teacher(scope, menu, head, %{subject: "Maths"})

    {:ok, _s_maco} = Enrollment.add_student(scope, maco, %{full_name: "Awa", sex: :f})
    {:ok, _s_menu} = Enrollment.add_student(scope, menu, %{full_name: "Beti", sex: :f})

    [%{enrollment: enr_maco}] = Enrollment.list_roster(scope, maco)
    [%{enrollment: enr_menu}] = Enrollment.list_roster(scope, menu)

    {:ok, course} = Curriculum.combine_course(scope, [tc_maco, tc_menu])

    :ok = Attendance.build_default_periods(scope)
    period = Attendance.list_periods(scope) |> Enum.find(&(&1.kind == :lesson))

    # Monday. Only MACO's slot is placed at this cell (see the note in
    # attendance_combined_test.exs) — navigating to MACO's own attendance
    # page is what puts this LiveView in combined mode.
    {:ok, _slot_maco} =
      Timetabling.place_slot(scope, maco, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc_maco.id
      })

    date = ~D[2025-09-08]

    {:ok, profile} = Accounts.fetch_school_profile(scope)
    {:ok, _} = Accounts.verify_school(profile, head.id, scope: scope)

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      school: school,
      course: course,
      maco: maco,
      menu: menu,
      period: period,
      date: date,
      scope: scope,
      enr_maco: enr_maco,
      enr_menu: enr_menu
    }
  end

  defp att_path(cg, period, date),
    do: "/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}"

  test "shows the union roster of both member classes, grouped by class", %{
    conn: conn,
    maco: maco,
    menu: menu,
    period: period,
    date: date,
    course: course
  } do
    {:ok, view, _html} = live(conn, att_path(maco, period, date))

    assert has_element?(view, "#class-attendance", course.label)
    assert has_element?(view, "#attendance-class-#{maco.id}", maco.label)
    assert has_element?(view, "#attendance-class-#{menu.id}", menu.label)
  end

  test "marking a MENU student absent and recording lands the entry on MENU's enrollment, MACO's on theirs",
       %{
         conn: conn,
         maco: maco,
         period: period,
         date: date,
         course: course,
         scope: scope,
         enr_maco: enr_maco,
         enr_menu: enr_menu
       } do
    {:ok, view, _html} = live(conn, att_path(maco, period, date))

    view |> element("#att-#{enr_menu.id}-absent") |> render_click()
    view |> element("#record-roll") |> render_click()

    groups = Attendance.combined_period_roll(scope, course, period, date)
    all_students = Enum.flat_map(groups, & &1.students)

    assert Enum.find(all_students, &(&1.enrollment_id == enr_menu.id)).status == :absent
    assert Enum.find(all_students, &(&1.enrollment_id == enr_maco.id)).status == :present
  end
end
