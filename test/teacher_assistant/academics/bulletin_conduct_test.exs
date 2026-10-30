defmodule TeacherAssistant.Academics.BulletinConductTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics.TypedAbsence

  alias TeacherAssistant.{
    Attendance,
    Councils,
    Curriculum,
    Discipline,
    Enrollment,
    Organization,
    TeacherFixtures,
    Timetabling
  }

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "L"})

    scope = school_scope(head, ws)
    :ok = TeacherFixtures.verify_school!(scope)
    scope = school_scope(head, ws)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    scope = %{scope | current_academic_year: year}
    :ok = Organization.build_default_calendar(scope, year)
    [t1 | _] = terms = Organization.list_terms(scope, year)
    [s1, s2 | _] = t1.sequences |> Enum.sort_by(& &1.position_in_term)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    [%{enrollment: awa}, %{enrollment: bob}] = Enrollment.list_roster(scope, cg)
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p1.id,
        teaching_context_id: tc.id
      })

    # An app absence on Monday 8 September, inside the first séquence.
    {:ok, _} = Attendance.record_period(scope, cg, p1, tc, ~D[2025-09-08], [{awa.id, :absent}])

    %{scope: scope, year: year, terms: terms, t1: t1, s1: s1, s2: s2, cg: cg, awa: awa, bob: bob}
  end

  defp typed(ctx, source) do
    {:ok, cg} = Enrollment.set_absence_hours_source(ctx.scope, ctx.cg, source)
    cg
  end

  defp set_seq(ctx, e, seq, hours) do
    {:ok, _} =
      TypedAbsence
      |> Ash.Changeset.for_create(
        :set_for_sequence,
        %{enrollment_id: e.id, sequence_id: seq.id, hours: Decimal.new(hours)},
        scope: ctx.scope
      )
      |> Ash.create()
  end

  defp set_term(ctx, e, term, hours) do
    {:ok, _} =
      TypedAbsence
      |> Ash.Changeset.for_create(
        :set_for_term,
        %{enrollment_id: e.id, term_id: term.id, hours: Decimal.new(hours)},
        scope: ctx.scope
      )
      |> Ash.create()
  end

  test "roll-call class equals class_conduct plus source", ctx do
    computed = Attendance.class_conduct(ctx.scope, ctx.cg, {:sequence, ctx.s1})
    result = Attendance.bulletin_conduct(ctx.scope, ctx.cg, {:sequence, ctx.s1})

    assert result[ctx.awa.id] ==
             Map.merge(computed[ctx.awa.id], %{source: :roll_call, recorded?: true})

    assert Decimal.gt?(result[ctx.awa.id].unjustified_hours, 0)
  end

  test "typed class ignores app roll calls", ctx do
    cg = typed(ctx, :typed_per_sequence)
    set_seq(ctx, ctx.awa, ctx.s1, 3)

    assert %{
             unjustified_hours: u,
             justified_hours: j,
             retards: 0,
             source: :typed,
             recorded?: true
           } =
             Attendance.bulletin_conduct(ctx.scope, cg, {:sequence, ctx.s1})[ctx.awa.id]

    assert Decimal.equal?(u, 3)
    assert Decimal.equal?(j, 0)
  end

  test "a typed student with nothing typed counts 0 and recorded? false", ctx do
    cg = typed(ctx, :typed_per_sequence)

    assert %{unjustified_hours: u, recorded?: false} =
             Attendance.bulletin_conduct(ctx.scope, cg, {:sequence, ctx.s1})[ctx.bob.id]

    assert Decimal.equal?(u, 0)
  end

  test "annual sums the trimesters", ctx do
    cg = typed(ctx, :typed_per_term)
    [t1, t2 | _] = ctx.terms
    set_term(ctx, ctx.awa, t1, 4)
    set_term(ctx, ctx.awa, t2, "2.5")

    assert %{unjustified_hours: u} =
             Attendance.bulletin_conduct(ctx.scope, cg, {:annual, ctx.year})[ctx.awa.id]

    assert Decimal.equal?(u, Decimal.new("6.5"))
  end

  test "passage_inputs reads typed hours", ctx do
    cg = typed(ctx, :typed_per_term)
    set_term(ctx, ctx.awa, ctx.t1, 70)

    inputs = Councils.passage_inputs(ctx.scope, cg, {:annual, ctx.year})
    assert Decimal.equal?(inputs[ctx.awa.student_id].unjustified_hours, 70)
  end

  test "conduct_sheet suggestion uses typed séquence hours", ctx do
    cg = typed(ctx, :typed_per_sequence)
    set_seq(ctx, ctx.bob, ctx.s1, 5)

    rows = Discipline.conduct_sheet(ctx.scope, cg, ctx.s1)
    bob = Enum.find(rows, &(&1.enrollment.id == ctx.bob.id))
    awa = Enum.find(rows, &(&1.enrollment.id == ctx.awa.id))
    assert Decimal.equal?(bob.unjustified_hours, 5)
    assert Decimal.equal?(awa.unjustified_hours, 0)
  end

  test "per_term conduct sheet has 0 hours", ctx do
    cg = typed(ctx, :typed_per_term)
    set_term(ctx, ctx.awa, ctx.t1, 5)

    rows = Discipline.conduct_sheet(ctx.scope, cg, ctx.s1)
    assert Enum.all?(rows, &Decimal.equal?(&1.unjustified_hours, 0))
  end

  test "typed_absences_missing counts students without a complete figure", ctx do
    assert Attendance.typed_absences_missing(ctx.scope, ctx.cg, {:trimester, ctx.t1}) == 0

    cg = typed(ctx, :typed_per_sequence)
    set_seq(ctx, ctx.awa, ctx.s1, 1)
    set_seq(ctx, ctx.awa, ctx.s2, 0)
    set_seq(ctx, ctx.bob, ctx.s1, 1)

    assert Attendance.typed_absences_missing(ctx.scope, cg, {:trimester, ctx.t1}) == 1
  end
end
