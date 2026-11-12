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
    # These tests cover the app roll call; the paper rule has its own describe below.
    {:ok, cg} = Enrollment.set_paper_roll_call(scope, cg, false)
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

  # Queries run by this process during `fun` that read `table` (A3).
  defp count_queries(table, fun) do
    parent = self()
    counter = :counters.new(1, [])
    needle = ~s(FROM "#{table}")

    handler = {__MODULE__, table, make_ref()}

    :telemetry.attach(
      handler,
      [:teacher_assistant, :repo, :query],
      fn _e, _m, %{query: q}, _ ->
        if self() == parent and q =~ needle, do: :counters.add(counter, 1, 1)
      end,
      nil
    )

    result = fun.()
    :telemetry.detach(handler)
    {result, :counters.get(counter, 1)}
  end

  test "absences_to_justify reads no student or guardian rows and counts a long late (A3)", ctx do
    set_school_life(ctx.scope, %{late_as_absence_minutes: 15, absence_alert_hours: 2})

    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, ~D[2025-09-15], [
        {ctx.e.id, :late, 30}
      ])

    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, ~D[2025-09-22], [
        {ctx.e.id, :absent}
      ])

    today = ~D[2025-09-30]
    {first, last} = Attendance.current_sequence_range(ctx.scope, today)
    rows = Attendance.absence_days(ctx.scope, first, last, today)
    assert length(rows) == 2

    {r, student_queries} =
      count_queries("students", fn -> Attendance.absences_to_justify(ctx.scope, today) end)

    {_, guardian_queries} =
      count_queries("guardians", fn -> Attendance.absences_to_justify(ctx.scope, today) end)

    assert r.count == 2
    assert r.flagged_students == 0
    assert student_queries == 0
    assert guardian_queries == 0
  end

  test "absence_counts: today's absent students and the open days (A3)", ctx do
    {:ok, _} = Enrollment.add_student(ctx.scope, ctx.cg, %{full_name: "Bello", sex: :m})

    %{enrollment: other} =
      Enum.find(Enrollment.list_roster(ctx.scope, ctx.cg), &(&1.enrollment.id != ctx.e.id))

    today = ~D[2025-09-22]

    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, ~D[2025-09-15], [
        {ctx.e.id, :absent}
      ])

    {:ok, 1} = Attendance.justify_day(ctx.scope, ctx.e, ~D[2025-09-15], :maladie)

    for p <- [ctx.p1, ctx.p2],
        do:
          {:ok, _} =
            Attendance.record_period(ctx.scope, ctx.cg, p, ctx.tc, today, [
              {ctx.e.id, :absent},
              {other.id, :absent}
            ])

    assert %{today_absent_students: 2, to_justify: 2} =
             Attendance.absence_counts(ctx.scope, today)
  end

  test "absence_counts and absences_to_justify are zero before the first séquence (A3)", ctx do
    # before the year's first séquence: the range is empty (first > last)
    today = ~D[2025-09-01]

    assert %{today_absent_students: 0, to_justify: 0} =
             Attendance.absence_counts(ctx.scope, today)

    assert %{count: 0, flagged_students: 0} = Attendance.absences_to_justify(ctx.scope, today)
  end

  test "absences_to_justify counts unjustified rows and flagged students", ctx do
    {:ok, _} = Enrollment.add_student(ctx.scope, ctx.cg, %{full_name: "Bello", sex: :m})

    %{enrollment: other} =
      Enum.find(Enrollment.list_roster(ctx.scope, ctx.cg), &(&1.enrollment.id != ctx.e.id))

    for d <- [~D[2025-09-15], ~D[2025-09-22], ~D[2025-09-29]],
        do:
          {:ok, _} =
            Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, d, [
              {ctx.e.id, :absent},
              {other.id, if(d == ~D[2025-09-15], do: :absent, else: :present)}
            ])

    {:ok, 1} = Attendance.justify_day(ctx.scope, other, ~D[2025-09-15], :maladie)
    set_school_life(ctx.scope, %{absence_alert_hours: 2})

    today = ~D[2025-09-30]
    {first, last} = Attendance.current_sequence_range(ctx.scope, today)
    rows = Attendance.absence_days(ctx.scope, first, last, today)
    r = Attendance.absences_to_justify(ctx.scope, today)

    assert r.count == Enum.count(rows, &(not &1.justified?))
    assert r.count == 3

    assert r.flagged_students ==
             rows
             |> Enum.filter(&(&1.flagged? and not &1.justified?))
             |> Enum.uniq_by(& &1.enrollment.id)
             |> length()

    assert r.flagged_students == 1
    assert r.alert_hours == 2
  end

  test "absences_to_justify is zero without a current séquence", ctx do
    assert %{count: 0, flagged_students: 0} =
             Attendance.absences_to_justify(
               %{ctx.scope | current_academic_year: nil},
               ~D[2025-09-30]
             )
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

  describe "roll call outside the timetable (spec 2026-11-12)" do
    # U (Anglais) has the Monday slot at p3; V has an assignment on 6e A and no slot;
    # S manages conduct. The head's slots are p1 and p2 (setup).
    setup %{scope: scope, cg: cg} do
      [p1, p2, p3, p4 | _] =
        scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

      year = scope.current_academic_year
      scope_u = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
      scope_v = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
      scope_s = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})

      {:ok, tc_u} =
        Curriculum.assign_teacher(scope, cg, scope_u.current_user, %{subject: "Anglais"})

      {:ok, tc_v} = Curriculum.assign_teacher(scope, cg, scope_v.current_user, %{subject: "SVT"})

      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: :monday,
          period_id: p3.id,
          teaching_context_id: tc_u.id
        })

      %{
        scope_u: %{scope_u | current_academic_year: year},
        scope_v: %{scope_v | current_academic_year: year},
        scope_s: %{scope_s | current_academic_year: year},
        tc_u: tc_u,
        tc_v: tc_v,
        p3: p3,
        p4: p4,
        p1: p1,
        p2: p2
      }
    end

    defp cell_of(day, cg, period),
      do: Enum.find(day.rows, &(&1.class_group.id == cg.id)).cells[period.id]

    test "a roll call under another context covers the slot and adds a moved cell", ctx do
      # U teaches 6e A at p2, the head's slot.
      {:ok, _} =
        Attendance.record_period(ctx.scope_u, ctx.cg, ctx.p2, ctx.tc_u, @monday, [
          {ctx.e.id, :absent}
        ])

      now = at(@monday, ~T[09:00:00])
      day = Attendance.school_day(ctx.scope, @monday, now)
      held = cell_of(day, ctx.cg, ctx.p2)
      assert %{status: :done, moved?: true, absent: 1, subject: "Anglais", slot_id: nil} = held
      assert held.teacher.id == ctx.scope_u.current_user.id
      assert held.covers.teacher.id == ctx.head.id
      assert held.covers.subject == "Maths"

      [_p1, p2_cell] = Attendance.teacher_day(ctx.scope, ctx.head, @monday, now)
      assert %{status: :covered, covered_by: %{subject: "Anglais"}} = p2_cell
      assert p2_cell.covered_by.teacher.id == ctx.scope_u.current_user.id

      assert [%{moved?: true, status: :done, period: %{id: p2}}] =
               Attendance.teacher_day(ctx.scope_u, ctx.scope_u.current_user, @monday, now)
               |> Enum.reject(&(&1.period.id == ctx.p3.id))

      assert p2 == ctx.p2.id
    end

    test "the swap: both teachers end up done, both vacated slots read déplacé, counts 2/0",
         ctx do
      head_scope = ctx.scope
      # The head teaches 6e A at p3 (U's slot) instead of p1; U teaches at p1 instead of p3.
      {:ok, _} =
        Attendance.record_period(head_scope, ctx.cg, ctx.p3, ctx.tc, @monday, [
          {ctx.e.id, :present}
        ])

      {:ok, _} = Attendance.mark_moved(head_scope, ctx.cg, ctx.p1, @monday, ctx.p3)

      {:ok, _} =
        Attendance.record_period(ctx.scope_u, ctx.cg, ctx.p1, ctx.tc_u, @monday, [
          {ctx.e.id, :present}
        ])

      {:ok, _} = Attendance.mark_moved(ctx.scope_u, ctx.cg, ctx.p3, @monday, ctx.p1)

      now = at(@monday, ~T[09:00:00])
      day = Attendance.school_day(ctx.scope, @monday, now)
      assert %{done: 2, missed: [], expected: 2} = Attendance.roll_call_counts(day)
      assert %{moved?: true, subject: "Anglais"} = cell_of(day, ctx.cg, ctx.p1)
      assert %{moved?: true, subject: "Maths"} = cell_of(day, ctx.cg, ctx.p3)

      head_day = Attendance.teacher_day(ctx.scope, ctx.head, @monday, now)

      assert %{status: :not_held, moved_to: %{id: p3}} =
               Enum.find(head_day, &(&1.period.id == ctx.p1.id and &1.slot_id))

      assert p3 == ctx.p3.id
      assert %{status: :done, moved?: true} = Enum.find(head_day, &(&1.period.id == ctx.p3.id))

      u_day = Attendance.teacher_day(ctx.scope_u, ctx.scope_u.current_user, @monday, now)

      assert %{status: :not_held, moved_to: %{id: p1}} =
               Enum.find(u_day, &(&1.period.id == ctx.p3.id and &1.slot_id))

      assert p1 == ctx.p1.id
    end

    test "a covered slot is neither missed this week nor in the surveillant's missed list", ctx do
      {:ok, _} =
        Attendance.record_period(ctx.scope_u, ctx.cg, ctx.p2, ctx.tc_u, @monday, [
          {ctx.e.id, :present}
        ])

      tuesday = Date.add(@monday, 1)

      missed =
        Attendance.teacher_missed_this_week(
          ctx.scope,
          ctx.head,
          tuesday,
          at(tuesday, ~T[09:00:00])
        )

      assert Enum.map(missed, & &1.period.id) == [ctx.p1.id]

      day = Attendance.school_day(ctx.scope, @monday, at(@monday, ~T[12:00:00]))
      assert Enum.map(day.missed, & &1.period.id) == [ctx.p1.id, ctx.p3.id]
    end

    test "a teacher with no slot sees only their moved cell", ctx do
      {:ok, _} =
        Attendance.record_period(ctx.scope_v, ctx.cg, ctx.p4, ctx.tc_v, @monday, [
          {ctx.e.id, :present}
        ])

      assert [%{moved?: true, status: :done, subject: "SVT", covers: nil}] =
               Attendance.teacher_day(
                 ctx.scope_v,
                 ctx.scope_v.current_user,
                 @monday,
                 at(@monday, ~T[12:00:00])
               )

      day = Attendance.school_day(ctx.scope, @monday, at(@monday, ~T[12:00:00]))
      assert %{moved?: true} = cell_of(day, ctx.cg, ctx.p4)
    end

    test "a conduct manager's roll call (no context) is the slot's own done", ctx do
      {:ok, _} =
        Attendance.record_period(ctx.scope_s, ctx.cg, ctx.p2, nil, @monday, [{ctx.e.id, :present}])

      now = at(@monday, ~T[09:00:00])

      assert %{status: :done, moved?: false} =
               cell_of(Attendance.school_day(ctx.scope, @monday, now), ctx.cg, ctx.p2)

      assert [_, %{status: :done}] = Attendance.teacher_day(ctx.scope, ctx.head, @monday, now)
    end
  end

  describe "paper roll call (spec 2026-10-28)" do
    setup %{scope: scope, cg: cg} do
      {:ok, cg} = Enrollment.set_paper_roll_call(scope, cg, true)
      %{cg: cg}
    end

    defp status_of(day, cg, period),
      do: Enum.find(day.rows, &(&1.class_group.id == cg.id)).cells[period.id].status

    test "a paper class's untaken lesson is on paper, not missed", ctx do
      day = Attendance.school_day(ctx.scope, @monday, at(@monday, ~T[13:00:00]))

      assert status_of(day, ctx.cg, ctx.p1) == :on_paper
      assert day.missed == []

      assert %{done: 0, on_paper: 2, expected: 2, missed: []} =
               Attendance.roll_call_counts(day)
    end

    test "the Monday after, it is missed again", ctx do
      [lesson | _] =
        Attendance.class_lessons(
          ctx.scope,
          ctx.cg,
          @monday,
          @monday,
          at(~D[2025-09-22], ~T[09:00:00])
        )

      assert lesson.status == :missed
    end

    test "a class off paper keeps today's rule", ctx do
      {:ok, _} = Enrollment.set_paper_roll_call(ctx.scope, ctx.cg, false)
      day = Attendance.school_day(ctx.scope, @monday, at(@monday, ~T[13:00:00]))
      assert status_of(day, ctx.cg, ctx.p1) == :missed
    end

    test "a lesson marked not held is neither missed nor on paper", ctx do
      {:ok, _} =
        TeacherAssistant.Academics.LessonNotHeld
        |> Ash.Changeset.for_create(
          :mark,
          %{class_group_id: ctx.cg.id, period_id: ctx.p1.id, date: @monday},
          scope: ctx.scope
        )
        |> Ash.create()

      day = Attendance.school_day(ctx.scope, @monday, at(@monday, ~T[13:00:00]))
      assert status_of(day, ctx.cg, ctx.p1) == :not_held
      assert %{on_paper: 1, expected: 1} = Attendance.roll_call_counts(day)
    end

    test "a teacher's day follows the paper rule", ctx do
      [cell | _] = Attendance.teacher_day(ctx.scope, ctx.head, @monday, at(@monday, ~T[13:00:00]))
      assert cell.status == :on_paper

      assert Attendance.teacher_missed_this_week(
               ctx.scope,
               ctx.head,
               Date.add(@monday, 1),
               at(Date.add(@monday, 1), ~T[13:00:00])
             ) == []
    end
  end
end
