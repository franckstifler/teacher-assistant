defmodule TeacherAssistant.Academics.AbsenceTotalsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics.{AbsenceTotals, TypedAbsence}

  alias TeacherAssistant.{
    Attendance,
    Curriculum,
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

  test "default threshold is 20 h per séquence" do
    assert AbsenceTotals.default_threshold(1) == Decimal.new(20)
    assert AbsenceTotals.default_threshold(3) == Decimal.new(60)
    assert AbsenceTotals.default_threshold(0) == Decimal.new(20)
  end

  test "parse_threshold takes a comma, falls back on anything else" do
    d = Decimal.new(20)
    assert AbsenceTotals.parse_threshold("12,5", d) == Decimal.new("12.5")
    assert AbsenceTotals.parse_threshold("8", d) == Decimal.new(8)
    assert AbsenceTotals.parse_threshold(" 7.5 ", d) == Decimal.new("7.5")

    for bad <- [
          nil,
          "",
          "abc",
          "-3",
          "0",
          "12abc",
          "inf",
          "Infinity",
          "NaN",
          "1e100000000",
          "1001"
        ],
        do: assert(AbsenceTotals.parse_threshold(bad, d) == d)
  end

  test "over_threshold keeps flagged students, most hours first, drops empty classes" do
    row = fn name, h -> %{student: %{full_name: name}, unjustified_hours: Decimal.new(h)} end

    a = %{
      class_group: %{id: "a"},
      source: :roll_call,
      rows: [row.("Ali", 3), row.("Ben", 25), row.("Cyr", 21), row.("Dia", 20)]
    }

    b = %{class_group: %{id: "b"}, source: :roll_call, rows: [row.("Dan", 5)]}

    assert [%{class_group: %{id: "a"}, rows: rows}] =
             AbsenceTotals.over_threshold([a, b], Decimal.new(20))

    assert Enum.map(rows, & &1.student.full_name) == ["Ben", "Cyr", "Dia"]
  end

  test "absence_totals gives the bulletin's figures in roll order", ctx do
    [g] = Attendance.absence_totals(ctx.scope, {:sequence, ctx.s1}, [ctx.cg])
    assert g.class_group.id == ctx.cg.id
    assert g.source == :roll_call
    assert Enum.map(g.rows, & &1.student.full_name) == ["Awa", "Bob"]
    [awa, bob] = g.rows
    assert awa.enrollment.id == ctx.awa.id
    assert Decimal.gt?(awa.unjustified_hours, 0)
    assert Decimal.equal?(bob.unjustified_hours, 0)
    assert awa.recorded? and is_integer(awa.retards)
  end

  test "a typed class shows typed hours and an unrecorded student", ctx do
    cg = typed(ctx, :typed_per_sequence)
    set_seq(ctx, ctx.awa, ctx.s1, 25)
    [g] = Attendance.absence_totals(ctx.scope, {:sequence, ctx.s1}, [cg])
    assert g.source == :typed
    [awa, bob] = g.rows
    assert Decimal.equal?(awa.unjustified_hours, 25) and awa.recorded?
    refute bob.recorded?

    assert [%{rows: [%{student: %{full_name: "Awa"}}]}] =
             AbsenceTotals.over_threshold([g], Decimal.new(20))
  end
end
