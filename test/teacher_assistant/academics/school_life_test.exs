defmodule TeacherAssistant.Academics.SchoolLifeTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{
    Attendance,
    Curriculum,
    Discipline,
    Enrollment,
    Organization,
    Timetabling
  }

  alias TeacherAssistant.TeacherFixtures

  # 2025-09-15 is a Monday; lesson 1 runs 07:30–08:20, lesson 2 08:20–09:10.
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
    [p1, p2 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    for p <- [p1, p2] do
      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: :monday,
          period_id: p.id,
          teaching_context_id: tc.id
        })
    end

    %{scope: scope, head: head, cg: cg, tc: tc, e: e, p1: p1, p2: p2}
  end

  defp at(date, time), do: NaiveDateTime.new!(date, time)

  test "roll call statuses follow entries and the clock", ctx do
    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :absent}])

    day = Attendance.school_day(ctx.scope, @monday, at(@monday, ~T[08:30:00]))
    [row] = day.rows
    assert %{status: :done, absent: 1} = row.cells[ctx.p1.id]
    assert %{status: :in_progress} = row.cells[ctx.p2.id]
    assert day.missed == []

    day = Attendance.school_day(ctx.scope, @monday, at(@monday, ~T[10:00:00]))
    assert [%{status: :missed, subject: "Maths"}] = day.missed

    assert [%{status: :done}, %{status: :upcoming}] =
             Attendance.teacher_day(ctx.scope, ctx.head, @monday, at(@monday, ~T[07:00:00]))

    assert Attendance.school_day(ctx.scope, ~D[2025-09-14], at(~D[2025-09-14], ~T[10:00:00])).rows ==
             []
  end

  test "roll_call_counts matches the day grid", ctx do
    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :present}])

    now = at(@monday, ~T[10:00:00])
    day = Attendance.school_day(ctx.scope, @monday, now)
    counts = Attendance.roll_call_counts(ctx.scope, @monday, now)
    assert counts.done == 1
    assert counts.missed == day.missed
    assert counts.expected == counts.done + length(day.missed)
    assert counts.expected == 2
  end

  test "missed this week covers Monday to yesterday", ctx do
    wednesday = ~D[2025-09-17]

    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :present}])

    assert [%{date: @monday, period: p}] =
             Attendance.teacher_missed_this_week(
               ctx.scope,
               ctx.head,
               wednesday,
               at(wednesday, ~T[09:00:00])
             )

    assert p.id == ctx.p2.id

    assert Attendance.teacher_missed_this_week(
             ctx.scope,
             ctx.head,
             @monday,
             at(@monday, ~T[18:00:00])
           ) == []
  end

  test "absence rows carry the reason, the séquence's unjustified hours and the alert", ctx do
    days = [~D[2025-09-15], ~D[2025-09-22], ~D[2025-09-29]]

    for d <- days,
        do:
          {:ok, _} =
            Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, d, [{ctx.e.id, :absent}])

    today = ~D[2025-09-30]

    # 3 × 50 min = 2.5 h, under the default 10 h alert.
    assert [%{flagged?: false, justified?: false, unjustified_hours: hours} | _] =
             Attendance.absence_days(ctx.scope, ~D[2025-09-08], today, today)

    assert Decimal.equal?(hours, Decimal.new("2.5"))

    set_school_life(ctx.scope, %{absence_alert_hours: 2})

    assert [%{flagged?: true} | _] =
             Attendance.absence_days(ctx.scope, ~D[2025-09-08], today, today)

    assert {:error, :invalid_reason} = Attendance.justify_day(ctx.scope, ctx.e, @monday, nil)
    assert {:ok, 1} = Attendance.justify_day(ctx.scope, ctx.e, @monday, :maladie)

    rows = Attendance.absence_days(ctx.scope, ~D[2025-09-08], today, today)

    assert %{justified?: true, reason: :maladie, flagged?: false} =
             Enum.find(rows, &(&1.date == @monday))
  end

  test "an unjustified absence is late for justification after N lesson days", ctx do
    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :absent}])

    row = fn today ->
      ctx.scope |> Attendance.absence_days(~D[2025-09-08], today, today) |> hd()
    end

    refute row.(~D[2025-09-25]).overdue?

    set_school_life(ctx.scope, %{justification_deadline_days: 2})
    refute row.(~D[2025-09-17]).overdue?
    assert row.(~D[2025-09-18]).overdue?

    {:ok, 1} = Attendance.justify_day(ctx.scope, ctx.e, @monday, :famille)
    refute row.(~D[2025-09-18]).overdue?
  end

  test "overdue?/4 skips holidays and days without lessons" do
    alias TeacherAssistant.Academics.{SchoolCalendar, SchoolLife}

    cal =
      SchoolCalendar.new(nil, false, [
        %{label: "Congé", start_date: ~D[2025-10-27], end_date: ~D[2025-10-31]}
      ])

    # Friday 24 Oct, deadline 3. Lessons run Monday–Saturday by default; the
    # holiday week and the Sundays don't count: 25 Oct, 1 Nov, 3 Nov = 3 days.
    refute SchoolLife.overdue?(~D[2025-10-24], ~D[2025-11-03], 3, cal)
    assert SchoolLife.overdue?(~D[2025-10-24], ~D[2025-11-04], 3, cal)
    refute SchoolLife.overdue?(~D[2025-10-24], ~D[2026-01-01], nil, cal)
  end

  defp set_school_life(scope, attrs) do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, attrs, scope: scope)
      |> Ash.update()
  end

  test "parents notified is recorded with the date and author", ctx do
    {:ok, s} = Discipline.add_sanction(ctx.scope, ctx.e, %{type: :avertissement, date: @monday})
    {:ok, s} = Discipline.mark_parents_notified(ctx.scope, s)
    assert s.parents_notified_on
    assert s.parents_notified_by_user_id == ctx.head.id
    assert [%{id: id}] = Discipline.recent_sanctions!(scope: ctx.scope)
    assert id == s.id
  end

  describe "school calendar (spec J1)" do
    test "a holiday expects no roll call", ctx do
      {:ok, _} =
        TeacherAssistant.Organization.create_holiday(
          ctx.scope,
          ctx.scope.current_academic_year,
          %{
            label: "Journée pédagogique",
            start_date: @monday,
            end_date: @monday
          }
        )

      late = at(@monday, ~T[23:00:00])
      assert Attendance.school_day(ctx.scope, @monday, late).rows == []
      assert Attendance.school_day(ctx.scope, @monday, late).missed == []
      assert Attendance.teacher_day(ctx.scope, ctx.head, @monday, late) == []
      assert Attendance.day_off(ctx.scope, @monday) == {:holiday, "Journée pédagogique"}

      tuesday = Date.add(@monday, 1)

      assert Attendance.teacher_missed_this_week(
               ctx.scope,
               ctx.head,
               tuesday,
               at(tuesday, ~T[08:00:00])
             ) == []
    end

    test "an unticked weekday is a day without lessons", ctx do
      {:ok, _} =
        Attendance.update_school_days(ctx.scope, %{
          "lesson_days" => ~w(tuesday wednesday),
          "default_lesson_minutes" => "50"
        })
        |> case do
          {:error, {:slots_in_closed_cells, _}} ->
            # The setup's Monday slot blocks closing Monday: clear it first.
            for p <- [ctx.p1, ctx.p2],
                do:
                  :ok = TeacherAssistant.Timetabling.clear_slot(ctx.scope, ctx.cg, :monday, p.id)

            Attendance.update_school_days(ctx.scope, %{
              "lesson_days" => ~w(tuesday wednesday),
              "default_lesson_minutes" => "50"
            })

          other ->
            other
        end

      assert Attendance.day_off(ctx.scope, @monday) == :no_lessons
      assert Attendance.day_off(ctx.scope, Date.add(@monday, 1)) == nil
    end
  end
end
