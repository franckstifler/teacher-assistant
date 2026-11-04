defmodule TeacherAssistantWeb.School.AttendanceSentHomeTest do
  @moduledoc "Fees 2: students sent home for fees show « Renvoyé pour frais » in the roll call."
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.FeeControl
  alias TeacherAssistant.Timetabling
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

  defp att_path(cg, period, date),
    do: "/school/classes/#{cg.id}/attendance/#{period.id}?date=#{Date.to_iso8601(date)}"

  defp status_of(scope, cg, period, date, enrollment) do
    roll = Attendance.period_roll(scope, cg, period, date)
    Enum.find(roll.students, &(&1.enrollment_id == enrollment.id)).status
  end

  test "a roll opened after a send-out shows the student as Renvoyé pour frais and records it",
       ctx do
    {:ok, _} = FeeControl.record_send_out(ctx.scope, ctx.enrollment, ctx.date)
    {:ok, view, _html} = live(ctx.conn, att_path(ctx.cg, ctx.period, ctx.date))

    assert has_element?(view, "#sent-home-#{ctx.enrollment.id}", "Renvoyé pour frais")
    refute has_element?(view, "#att-#{ctx.enrollment.id}-absent")
    assert has_element?(view, "#roll-counts", "1 renvoyé pour frais")

    view |> element("#all-present") |> render_click()
    assert has_element?(view, "#sent-home-#{ctx.enrollment.id}")

    view |> element("#record-roll") |> render_click()
    assert status_of(ctx.scope, ctx.cg, ctx.period, ctx.date, ctx.enrollment) == :sent_home
  end

  test "a roll taken before the send-out is untouched", ctx do
    {:ok, view, _html} = live(ctx.conn, att_path(ctx.cg, ctx.period, ctx.date))
    view |> element("#record-roll") |> render_click()

    {:ok, _} = FeeControl.record_send_out(ctx.scope, ctx.enrollment, ctx.date)
    {:ok, view, _html} = live(ctx.conn, att_path(ctx.cg, ctx.period, ctx.date))

    refute has_element?(view, "#sent-home-#{ctx.enrollment.id}")
    assert has_element?(view, "#student-row-#{ctx.enrollment.id}[data-status='present']")
  end

  test "a teacher can switch a sent-home student to present but not to absent", ctx do
    {:ok, other} =
      Enrollment.add_student(ctx.scope, ctx.cg, %{full_name: "Beba Ndoumbe", sex: :m})

    other_enr =
      Enum.find(Enrollment.list_roster(ctx.scope, ctx.cg), &(&1.student.id == other.id)).enrollment

    {:ok, _} = FeeControl.record_send_out(ctx.scope, ctx.enrollment, ctx.date)
    {:ok, view, _html} = live(ctx.conn, att_path(ctx.cg, ctx.period, ctx.date))

    render_click(view, "set", %{"enrollment_id" => ctx.enrollment.id, "status" => "absent"})
    assert has_element?(view, "#sent-home-#{ctx.enrollment.id}")

    render_click(view, "set", %{"enrollment_id" => other_enr.id, "status" => "sent_home"})
    assert has_element?(view, "#student-row-#{other_enr.id}[data-status='present']")

    view |> element("#att-#{ctx.enrollment.id}-present") |> render_click()
    refute has_element?(view, "#sent-home-#{ctx.enrollment.id}")

    view |> element("#record-roll") |> render_click()
    assert status_of(ctx.scope, ctx.cg, ctx.period, ctx.date, ctx.enrollment) == :present
  end

  test "after P, a sent-home student still cannot be marked absent, and can be put back", ctx do
    {:ok, _} = FeeControl.record_send_out(ctx.scope, ctx.enrollment, ctx.date)
    {:ok, view, _html} = live(ctx.conn, att_path(ctx.cg, ctx.period, ctx.date))

    view |> element("#att-#{ctx.enrollment.id}-present") |> render_click()
    render_click(view, "set", %{"enrollment_id" => ctx.enrollment.id, "status" => "absent"})
    refute has_element?(view, "#att-#{ctx.enrollment.id}-absent")
    assert has_element?(view, "#att-#{ctx.enrollment.id}-present[aria-pressed='true']")

    view |> element("#att-#{ctx.enrollment.id}-sent_home") |> render_click()
    assert has_element?(view, "#sent-home-#{ctx.enrollment.id}")

    view |> element("#record-roll") |> render_click()
    assert status_of(ctx.scope, ctx.cg, ctx.period, ctx.date, ctx.enrollment) == :sent_home
  end
end
