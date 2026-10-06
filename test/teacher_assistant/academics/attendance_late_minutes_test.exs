defmodule TeacherAssistant.Academics.AttendanceLateMinutesTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.TeacherFixtures

  @monday ~D[2025-09-15]

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "L"})

    scope = school_scope(head, ws)
    :ok = TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    scope = %{scope | current_academic_year: year}
    _ = Organization.build_default_calendar(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: e}] = Enrollment.list_roster(scope, cg)
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{day: :monday, period_id: p1.id, teaching_context_id: tc.id})

    %{scope: scope, cg: cg, tc: tc, e: e, p1: p1, year: year}
  end

  test "a late keeps its minutes; changing the status clears them", ctx do
    {:ok, 1} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :late, 20}])

    %{students: [%{status: :late, late_minutes: 20}]} =
      Attendance.period_roll(ctx.scope, ctx.cg, ctx.p1, @monday)

    {:ok, 1} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :absent, 20}])

    %{students: [%{status: :absent, late_minutes: nil}]} =
      Attendance.period_roll(ctx.scope, ctx.cg, ctx.p1, @monday)
  end

  test "the school's threshold turns a long late into absence hours in the totals", ctx do
    {:ok, 1} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :late, 20}])

    period = {:annual, ctx.year}
    assert Attendance.student_conduct(ctx.scope, ctx.e, period).retards == 1

    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(ctx.scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, %{late_as_absence_minutes: 15}, scope: ctx.scope)
      |> Ash.update()

    totals = Attendance.student_conduct(ctx.scope, ctx.e, period)
    assert totals.retards == 0
    assert Decimal.gt?(totals.unjustified_hours, 0)
    assert Decimal.gt?(Attendance.class_conduct(ctx.scope, ctx.cg, period)[ctx.e.id].unjustified_hours, 0)
  end
end
