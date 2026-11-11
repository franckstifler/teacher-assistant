defmodule TeacherAssistant.Academics.DeparturePeriodsTest do
  @moduledoc """
  A departed student is in every period that began before `left_on` and out of the
  others; rosters and roll calls drop them from `left_on` itself (A7).
  """
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Assessment, Attendance, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.{MarksFixtures, TeacherFixtures, Timetabling}
  alias TeacherAssistant.Academics.EntryProgress

  setup do
    %{scope: scope, year: year, head_user: head} = TeacherFixtures.setup_complete_school_fixture()
    :ok = TeacherFixtures.verify_school!(scope)
    scope = %{scope | current_academic_year: year}
    MarksFixtures.start_sequences!(scope, year)
    [term | _] = Organization.list_terms(scope, year)
    [s1, s2 | _] = Enum.sort_by(term.sequences, & &1.position_in_term)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e D", level: "6ème"})

    {:ok, %{enrollment: awa_e, student: awa}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})

    {:ok, %{student: bob}} = Enrollment.enroll_new(scope, cg, %{full_name: "Bilal", sex: :m})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

    # S2 moves to start strictly after S1 so the two séquences have distinct first days.
    {:ok, s2} =
      s2
      |> Ash.Changeset.for_update(:update, %{start_date: Date.add(s1.start_date, 7)},
        scope: scope
      )
      |> Ash.update()

    {:ok, a1} =
      Assessment.create_assessment(scope, tc, s1, %{label: "D1", max_score: Decimal.new(20)})

    {:ok, a2} =
      Assessment.create_assessment(scope, tc, s2, %{label: "D2", max_score: Decimal.new(20)})

    :ok =
      Assessment.upsert_marks(scope, a1, [
        %{student_id: awa.id, score: Decimal.new(14)},
        %{student_id: bob.id, score: Decimal.new(10)}
      ])

    # Awa leaves on S2's first day: in S1 and in trimester 1 (it starts with S1), out of S2.
    {:ok, _} =
      Enrollment.leave(scope, awa_e, %{departure_reason: :transfer, left_on: s2.start_date})

    [term | _] = Organization.list_terms(scope, year)

    %{
      scope: scope,
      year: year,
      term: term,
      s1: s1,
      s2: s2,
      cg: cg,
      tc: tc,
      a1: a1,
      a2: a2,
      awa: awa,
      bob: bob,
      awa_e: awa_e
    }
  end

  test "a student departed on a séquence's first day is out of it and in the earlier one", ctx do
    s1 = Assessment.class_results_for_period(ctx.scope, ctx.cg, {:sequence, ctx.s1})
    s2 = Assessment.class_results_for_period(ctx.scope, ctx.cg, {:sequence, ctx.s2})
    t1 = Assessment.class_results_for_period(ctx.scope, ctx.cg, {:trimester, ctx.term})

    assert Map.has_key?(s1.per_student, ctx.awa.id)
    refute Map.has_key?(s2.per_student, ctx.awa.id)
    assert Map.has_key?(t1.per_student, ctx.awa.id)
  end

  test "the period's first day is the first séquence's start", ctx do
    assert Organization.period_first_day(ctx.scope, {:sequence, ctx.s2}) == ctx.s2.start_date
    assert Organization.period_first_day(ctx.scope, {:trimester, ctx.term}) == ctx.s1.start_date
  end

  test "the roll call of the departure day leaves her out, the day before has her", ctx do
    :ok = Attendance.build_default_periods(ctx.scope)
    period = ctx.scope |> Attendance.list_periods() |> Enum.find(&(&1.kind == :lesson))
    day = ctx.s2.start_date
    weekday = Date.day_of_week(day)
    days = ~w(monday tuesday wednesday thursday friday saturday sunday)a

    {:ok, _} =
      Timetabling.place_slot(ctx.scope, ctx.cg, %{
        day: Enum.at(days, weekday - 1),
        period_id: period.id,
        teaching_context_id: ctx.tc.id
      })

    names = fn date ->
      ctx.scope
      |> Attendance.period_roll(ctx.cg, period, date)
      |> Map.fetch!(:students)
      |> Enum.map(& &1.student_name)
    end

    assert names.(day) == ["Bilal"]
    assert "Awa" in names.(Date.add(day, -7))
  end

  test "a mark for the earlier séquence is still accepted, for the later one refused", ctx do
    assert :ok =
             Assessment.upsert_marks(ctx.scope, ctx.a1, [
               %{student_id: ctx.awa.id, score: Decimal.new(15)}
             ])

    assert {:error, _} =
             Assessment.upsert_marks(ctx.scope, ctx.a2, [
               %{student_id: ctx.awa.id, score: Decimal.new(15)}
             ])
  end

  test "entry progress expects her in S1 only", ctx do
    cell = fn seq ->
      grid = Assessment.sequence_entry_grid(ctx.scope, ctx.year, seq)
      %{key: key} = Enum.find(grid.subjects, &(&1.label == "Maths"))
      row = Enum.find(grid.rows, &(&1.class_group.id == ctx.cg.id))
      Map.get(row.cells, key)
    end

    assert cell.(ctx.s1).expected == 2
    assert cell.(ctx.s2).expected == 1
  end

  test "a class with a departed student reaches 100 % over the trimester (review)", ctx do
    :ok =
      Assessment.upsert_marks(ctx.scope, ctx.a2, [
        %{student_id: ctx.bob.id, score: Decimal.new(9)}
      ])

    rate = fn seqs -> EntryProgress.class_rate(ctx.scope, ctx.year, ctx.cg, seqs) end
    assert rate.([ctx.s2]) == 100
    assert rate.([ctx.s1, ctx.s2]) == 100
  end

  test "a student who left during a séquence without a mark is not expected (review)", ctx do
    {:ok, %{enrollment: e, student: cleo}} =
      Enrollment.enroll_new(ctx.scope, ctx.cg, %{full_name: "Cléo", sex: :f})

    {:ok, _} =
      Enrollment.leave(ctx.scope, e, %{
        departure_reason: :dropout,
        left_on: Date.add(ctx.s1.start_date, 3)
      })

    grid = Assessment.sequence_entry_grid(ctx.scope, ctx.year, ctx.s1)
    %{key: key} = Enum.find(grid.subjects, &(&1.label == "Maths"))
    cell = Enum.find(grid.rows, &(&1.class_group.id == ctx.cg.id)).cells[key]
    assert {cell.entered, cell.expected, cell.pct} == {2, 2, 100}
    refute Map.has_key?(Map.new(grid.late, &{&1.teacher_id, &1}), ctx.tc.teacher_user_id)

    # Once she has a mark, it counts on both sides.
    :ok =
      Assessment.upsert_marks(ctx.scope, ctx.a1, [%{student_id: cleo.id, score: Decimal.new(8)}])

    assert EntryProgress.class_rate(ctx.scope, ctx.year, ctx.cg, [ctx.s1]) == 100
  end

  test "the trimester bulletin keeps her with her departure date", ctx do
    view = TeacherAssistant.ReportCards.live_view(ctx.scope, ctx.cg, {:trimester, ctx.term})
    entry = Enum.find(view.roster, &(&1.student.id == ctx.awa.id))
    assert entry.enrollment.left_on == ctx.s2.start_date
  end

  test "the trimester view keeps her discipline and conduct rows", ctx do
    view = TeacherAssistant.ReportCards.live_view(ctx.scope, ctx.cg, {:trimester, ctx.term})
    assert Map.has_key?(view.discipline, ctx.awa_e.id)
  end
end
