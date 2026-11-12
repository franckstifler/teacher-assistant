defmodule TeacherAssistant.Academics.PaperWeekTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.Academics.LessonNotHeld
  alias TeacherAssistant.TeacherFixtures

  # 2025-09-15 is a Monday (the test clock's day).
  @monday ~D[2025-09-15]
  @tuesday ~D[2025-09-16]

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

    for name <- ["Chantal", "Awa", "Beti"],
        do: {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: name, sex: :f})

    [awa, beti, chantal] = for r <- Enrollment.list_roster(scope, cg), do: r.enrollment
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    for day <- [:monday, :tuesday] do
      {:ok, _} =
        Timetabling.place_slot(scope, cg, %{
          day: day,
          period_id: p1.id,
          teaching_context_id: tc.id
        })
    end

    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})
    sg = %{sg | current_academic_year: year}

    %{
      scope: scope,
      sg: sg,
      head: head,
      year: year,
      cg: cg,
      tc: tc,
      p1: p1,
      awa: awa,
      beti: beti,
      chantal: chantal
    }
  end

  defp lesson(week, date, period) do
    week.days
    |> Enum.find(&(&1.date == date))
    |> Map.fetch!(:lessons)
    |> Enum.find(&(&1.period.id == period.id))
  end

  defp entries(ctx, date) do
    Attendance.for_class_range!(ctx.cg.id, date, date, scope: ctx.scope)
    |> Map.new(&{&1.enrollment_id, &1})
  end

  defp taken(date, period, marks \\ %{}),
    do: %{date: date, period_id: period.id, mode: :taken, marks: marks}

  test "the week lists the roster in class-list order with numbers", ctx do
    week = Attendance.paper_week(ctx.sg, ctx.cg, @monday)

    assert Enum.map(week.students, &{&1.number, &1.student_name}) ==
             [{1, "Awa"}, {2, "Beti"}, {3, "Chantal"}]

    assert {week.monday, week.saturday} == {@monday, ~D[2025-09-20]}
    # Every lesson day of the school, not only the days this class has lessons on.
    assert Enum.map(week.days, & &1.date) == Enum.to_list(Date.range(@monday, ~D[2025-09-20]))
    assert %{state: :empty, code: "MATH"} = lesson(week, @monday, ctx.p1)
  end

  test "each day has one cell per lesson period, the class's lesson in its cell", ctx do
    week = Attendance.paper_week(ctx.sg, ctx.cg, @monday)
    lesson_periods = ctx.scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    [monday, _, wednesday | _] = week.days

    assert Enum.map(monday.cells, & &1.period.id) == Enum.map(lesson_periods, & &1.id)
    assert [%{lesson: %{code: "MATH"}} | rest] = monday.cells
    assert Enum.all?(rest, &is_nil(&1.lesson))
    # A day without any lesson of the class still has its cells, all free.
    assert wednesday.lessons == [] and length(wednesday.cells) == length(lesson_periods)
  end

  test "with Wednesday afternoon off, Wednesday's cells stop at noon", ctx do
    {:ok, _} =
      Attendance.update_school_days(ctx.scope, %{
        "lesson_days" => ~w(monday tuesday wednesday thursday friday saturday),
        "wednesday_afternoon_off?" => "true",
        "default_lesson_minutes" => "50"
      })

    week = Attendance.paper_week(ctx.sg, ctx.cg, @monday)
    [monday, _, wednesday | _] = week.days
    assert length(wednesday.cells) < length(monday.cells)
    assert Enum.all?(wednesday.cells, &(Time.compare(&1.period.start_time, ~T[13:00:00]) == :lt))
  end

  test "a typed column records absents, lates and everyone else present", ctx do
    marks = %{ctx.awa.id => :absent, ctx.beti.id => :late}

    assert {:ok, %{saved: 1}} =
             Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [taken(@monday, ctx.p1, marks)])

    e = entries(ctx, @monday)
    assert e[ctx.awa.id].status == :absent
    assert e[ctx.beti.id].status == :late and is_nil(e[ctx.beti.id].late_minutes)
    assert e[ctx.chantal.id].status == :present
    assert Enum.all?(Map.values(e), &(&1.source == :paper))
    assert Enum.all?(Map.values(e), &(&1.recorded_by_user_id == ctx.sg.current_user.id))

    assert %{state: :paper} =
             lesson(Attendance.paper_week(ctx.sg, ctx.cg, @monday), @monday, ctx.p1)
  end

  test "an empty ticked column records everyone present", ctx do
    {:ok, _} = Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [taken(@monday, ctx.p1)])

    assert ctx |> entries(@monday) |> Map.values() |> Enum.map(& &1.status) |> Enum.uniq() == [
             :present
           ]
  end

  test "app lessons are never overwritten", ctx do
    roster = for s <- [ctx.awa, ctx.beti, ctx.chantal], do: {s.id, :present}
    {:ok, 3} = Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, roster)

    {:ok, %{saved: 0}} =
      Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [
        taken(@monday, ctx.p1, %{ctx.awa.id => :absent})
      ])

    awa = entries(ctx, @monday)[ctx.awa.id]
    assert awa.status == :present and awa.source == :app
  end

  test "a paper write never overwrites an app roll call, even one taken meanwhile", ctx do
    roster = for s <- [ctx.awa, ctx.beti, ctx.chantal], do: {s.id, :present}
    {:ok, 3} = Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, roster)

    # What a save would write if the app roll call landed after it read the week.
    assert {:error, _} =
             Attendance.record_period(
               ctx.sg,
               ctx.cg,
               ctx.p1,
               ctx.tc,
               @monday,
               [{ctx.awa.id, :absent}],
               source: :paper
             )

    awa = entries(ctx, @monday)[ctx.awa.id]
    assert awa.status == :present and awa.source == :app
  end

  test "sent home wins over A", ctx do
    {:ok, _} = TeacherAssistant.FeeControl.record_send_out(ctx.scope, ctx.beti, @monday)

    week = Attendance.paper_week(ctx.sg, ctx.cg, @monday)
    assert MapSet.member?(lesson(week, @monday, ctx.p1).sent_home, ctx.beti.id)

    {:ok, _} =
      Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [
        taken(@monday, ctx.p1, %{ctx.beti.id => :absent})
      ])

    assert entries(ctx, @monday)[ctx.beti.id].status == :sent_home
  end

  test "an unticked column writes nothing", ctx do
    {:ok, %{saved: 0}} =
      Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [
        %{date: @monday, period_id: ctx.p1.id, mode: :skip, marks: %{ctx.awa.id => :absent}}
      ])

    assert entries(ctx, @monday) == %{}
  end

  test "not held closes the lesson; ticking it later replaces that", ctx do
    not_held = %{date: @monday, period_id: ctx.p1.id, mode: :not_held, marks: %{}}
    {:ok, %{not_held: 1}} = Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [not_held])

    assert %{state: :not_held} =
             lesson(Attendance.paper_week(ctx.sg, ctx.cg, @monday), @monday, ctx.p1)

    assert entries(ctx, @monday) == %{}

    {:ok, %{saved: 1}} =
      Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [taken(@monday, ctx.p1)])

    assert map_size(entries(ctx, @monday)) == 3
    assert Ash.read!(LessonNotHeld, scope: ctx.scope) == []
  end

  test "a typed-in lesson marked not held later loses its paper entries", ctx do
    {:ok, _} = Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [taken(@monday, ctx.p1)])

    not_held = %{date: @monday, period_id: ctx.p1.id, mode: :not_held, marks: %{}}
    {:ok, %{not_held: 1}} = Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [not_held])

    assert entries(ctx, @monday) == %{}

    assert %{state: :not_held} =
             lesson(Attendance.paper_week(ctx.sg, ctx.cg, @monday), @monday, ctx.p1)
  end

  test "un-marking « non assuré » puts the lesson back", ctx do
    not_held = %{date: @monday, period_id: ctx.p1.id, mode: :not_held, marks: %{}}
    {:ok, _} = Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [not_held])

    {:ok, _} =
      Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [%{not_held | mode: :skip}])

    assert Ash.read!(LessonNotHeld, scope: ctx.scope) == []

    assert %{state: :empty} =
             lesson(Attendance.paper_week(ctx.sg, ctx.cg, @monday), @monday, ctx.p1)
  end

  test "a lesson that has not taken place yet cannot be closed", ctx do
    week = Attendance.paper_week(ctx.sg, ctx.cg, @monday)
    assert %{upcoming?: true} = lesson(week, @tuesday, ctx.p1)
    assert %{upcoming?: false} = lesson(week, @monday, ctx.p1)

    {:ok, %{saved: 0, not_held: 0}} =
      Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [
        taken(@tuesday, ctx.p1),
        %{date: @tuesday, period_id: ctx.p1.id, mode: :not_held, marks: %{}}
      ])

    assert entries(ctx, @tuesday) == %{}
  end

  test "closed days have no columns", ctx do
    {:ok, _} =
      Organization.create_holiday(ctx.scope, ctx.year, %{
        label: "Fête",
        start_date: @tuesday,
        end_date: @tuesday
      })

    tuesday =
      Enum.find(Attendance.paper_week(ctx.sg, ctx.cg, @monday).days, &(&1.date == @tuesday))

    assert %{closed: "Fête", lessons: []} = tuesday

    {:ok, %{saved: 0}} =
      Attendance.save_paper_week(ctx.sg, ctx.cg, @monday, [taken(@tuesday, ctx.p1)])

    assert entries(ctx, @tuesday) == %{}
  end

  test "combined lesson saves per class", ctx do
    {:ok, cg2} =
      Enrollment.create_class_group(ctx.scope, ctx.year, %{label: "6e B", level: "6ème"})

    {:ok, _} = Enrollment.add_student(ctx.scope, cg2, %{full_name: "Dora", sex: :f})
    {:ok, tc2} = Curriculum.assign_teacher(ctx.scope, cg2, ctx.head, %{subject: "Anglais"})
    {:ok, tc1} = Curriculum.assign_teacher(ctx.scope, ctx.cg, ctx.head, %{subject: "Anglais"})
    {:ok, course} = Curriculum.combine_course(ctx.scope, [tc1, tc2])
    [_, p2 | _] = ctx.scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    {:ok, _} = Timetabling.place_combined_slot(ctx.scope, course, :monday, p2.id)

    {:ok, %{saved: 1}} = Attendance.save_paper_week(ctx.sg, cg2, @monday, [taken(@monday, p2)])

    [dora_entry] =
      Attendance.for_class_range!(cg2.id, @monday, @monday, scope: ctx.scope)

    assert dora_entry.teaching_context_id == tc2.id
  end

  test "a teacher's app correction of a combined lesson typed in from paper is the app's", ctx do
    {:ok, cg2} =
      Enrollment.create_class_group(ctx.scope, ctx.year, %{label: "6e B", level: "6ème"})

    {:ok, _} = Enrollment.add_student(ctx.scope, cg2, %{full_name: "Dora", sex: :f})
    [dora] = for r <- Enrollment.list_roster(ctx.scope, cg2), do: r.enrollment
    {:ok, tc2} = Curriculum.assign_teacher(ctx.scope, cg2, ctx.head, %{subject: "Anglais"})
    {:ok, tc1} = Curriculum.assign_teacher(ctx.scope, ctx.cg, ctx.head, %{subject: "Anglais"})
    {:ok, course} = Curriculum.combine_course(ctx.scope, [tc1, tc2])
    [_, p2 | _] = ctx.scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    {:ok, _} = Timetabling.place_combined_slot(ctx.scope, course, :monday, p2.id)

    {:ok, _} = Attendance.save_paper_week(ctx.sg, cg2, @monday, [taken(@monday, p2)])

    marks =
      for s <- [ctx.awa, ctx.beti, ctx.chantal], do: {s.id, :present}

    {:ok, _} =
      Attendance.record_combined_period(ctx.scope, course, p2, @monday, [
        {dora.id, :absent} | marks
      ])

    assert %{state: :app} = lesson(Attendance.paper_week(ctx.sg, cg2, @monday), @monday, p2)
  end

  test "a teacher may not save a week; an unverified school neither", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})

    assert {:error, :forbidden} =
             Attendance.save_paper_week(teacher, ctx.cg, @monday, [taken(@monday, ctx.p1)])

    unverified = %{ctx.sg | school_verification_status: :pending}

    assert {:error, :unverified} =
             Attendance.save_paper_week(unverified, ctx.cg, @monday, [taken(@monday, ctx.p1)])
  end
end
