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
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p1.id,
        teaching_context_id: tc.id
      })

    %{scope: scope, cg: cg, tc: tc, e: e, p1: p1, year: year}
  end

  test "a roll call is saved whole or not at all", ctx do
    {:ok, _} = Enrollment.add_student(ctx.scope, ctx.cg, %{full_name: "Bob", sex: :m})

    %{enrollment: bob} =
      ctx.scope |> Enrollment.list_roster(ctx.cg) |> Enum.find(&(&1.enrollment.id != ctx.e.id))

    # Awa's row is fine; Bob's minutes break the 240 cap only when written.
    assert {:error, :record_failed} =
             Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [
               {ctx.e.id, :absent},
               {bob.id, :late, 500}
             ])

    %{students: students} = Attendance.period_roll(ctx.scope, ctx.cg, ctx.p1, @monday)
    assert Enum.all?(students, &is_nil(&1.status))
  end

  test "a late keeps its minutes; changing the status clears them", ctx do
    {:ok, 1} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :late, 20}])

    %{students: [%{status: :late, late_minutes: 20}]} =
      Attendance.period_roll(ctx.scope, ctx.cg, ctx.p1, @monday)

    {:ok, 1} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [
        {ctx.e.id, :absent, 20}
      ])

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
      |> Ash.Changeset.for_update(:update_school_life, %{late_as_absence_minutes: 15},
        scope: ctx.scope
      )
      |> Ash.update()

    totals = Attendance.student_conduct(ctx.scope, ctx.e, period)
    assert totals.retards == 0
    assert Decimal.gt?(totals.unjustified_hours, 0)

    assert Decimal.gt?(
             Attendance.class_conduct(ctx.scope, ctx.cg, period)[ctx.e.id].unjustified_hours,
             0
           )
  end

  test "a long late is listed with the day's absences and justified with them", ctx do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(ctx.scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, %{late_as_absence_minutes: 15},
        scope: ctx.scope
      )
      |> Ash.update()

    {:ok, 1} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :late, 20}])

    assert [%{date: @monday, justified?: false}] =
             Attendance.absence_days(ctx.scope, ~D[2025-09-08], @monday, @monday)

    assert {:ok, 1} = Attendance.justify_day(ctx.scope, ctx.e, @monday, :maladie)

    totals = Attendance.student_conduct(ctx.scope, ctx.e, {:annual, ctx.year})
    assert Decimal.gt?(totals.justified_hours, 0)
    assert Decimal.equal?(totals.unjustified_hours, 0)
    assert totals.retards == 0

    assert [%{justified?: true}] =
             Attendance.absence_days(ctx.scope, ~D[2025-09-08], @monday, @monday)
  end

  test "a short late is not listed with the absences", ctx do
    {:ok, 1} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :late, 5}])

    assert Attendance.absence_days(ctx.scope, ~D[2025-09-08], @monday, @monday) == []
  end

  test "a justification made while impersonated carries the operator (minors)", ctx do
    op = TeacherFixtures.admin_user_fixture()

    {:ok, 1} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :absent}])

    {:ok, 1} = Attendance.justify_day(impersonating(ctx.scope, op), ctx.e, @monday, :maladie)

    [entry] =
      Ash.read!(TeacherAssistant.Academics.AttendanceEntry,
        tenant: ctx.scope.current_workspace.id,
        authorize?: false
      )

    assert entry.justified_operator_user_id == op.id
  end
end
