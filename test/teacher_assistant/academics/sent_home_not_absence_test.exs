defmodule TeacherAssistant.Academics.SentHomeNotAbsenceTest do
  @moduledoc "Fees 2: « Renvoyé pour frais » entries never count as absences or lates."
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.Academics.SchoolLife
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

  defp record(ctx, status),
    do:
      {:ok, 1} =
        Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, status}])

  test "a sent-home lesson is not counted by conduct totals", ctx do
    record(ctx, :sent_home)
    totals = Attendance.student_conduct(ctx.scope, ctx.e, {:annual, ctx.year})
    assert Decimal.eq?(totals.unjustified_hours, 0) and Decimal.eq?(totals.justified_hours, 0)
    assert totals.retards == 0

    record(ctx, :absent)

    refute Decimal.eq?(
             Attendance.student_conduct(ctx.scope, ctx.e, {:annual, ctx.year}).unjustified_hours,
             0
           )
  end

  test "a sent-home lesson is not in the school-life absence lists", ctx do
    record(ctx, :sent_home)
    assert SchoolLife.absence_days(ctx.scope, ~D[2025-09-08], ~D[2025-09-30], @monday) == []
    assert SchoolLife.absences_to_justify(ctx.scope, @monday).count == 0

    record(ctx, :absent)
    assert [_] = SchoolLife.absence_days(ctx.scope, ~D[2025-09-08], ~D[2025-09-30], @monday)
  end

  test "justifying the day leaves a sent-home entry as it is", ctx do
    record(ctx, :sent_home)
    [reason | _] = TeacherAssistant.Academics.JustificationReason.values()
    assert {:ok, 0} = Attendance.justify_day(ctx.scope, ctx.e, @monday, reason)

    assert %{students: [%{status: :sent_home}]} =
             Attendance.period_roll(ctx.scope, ctx.cg, ctx.p1, @monday)
  end

  test "the class register counts a sent-home lesson as no absence", ctx do
    record(ctx, :sent_home)
    %{students: [student]} = Attendance.class_register(ctx.scope, ctx.cg, @monday)
    assert student.cells[ctx.p1.id] == :sent_home
  end
end
