defmodule TeacherAssistant.DisciplineConductSheetTest do
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

  # 2025-09-15 is a Monday; lesson 1 runs 07:30–08:20 (50 minutes).
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
    {:ok, other_cg} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
    {:ok, _} = Enrollment.add_student(scope, other_cg, %{full_name: "Zoé", sex: :f})
    [%{enrollment: awa}, %{enrollment: bob}] = Enrollment.list_roster(scope, cg)
    [%{enrollment: zoe}] = Enrollment.list_roster(scope, other_cg)
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p1.id,
        teaching_context_id: tc.id
      })

    seq = Organization.current_sequence(scope, year, @monday)

    %{scope: scope, cg: cg, tc: tc, p1: p1, awa: awa, bob: bob, zoe: zoe, seq: seq, year: year}
  end

  test "each row carries the séquence's facts, the current mark and the suggestion", ctx do
    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [
        {ctx.awa.id, :absent},
        {ctx.bob.id, :late}
      ])

    {:ok, _} = Discipline.add_sanction(ctx.scope, ctx.awa, %{type: :avertissement, date: @monday})

    # Outside the séquence: not counted.
    {:ok, _} =
      Discipline.add_sanction(ctx.scope, ctx.awa, %{
        type: :blame,
        date: Date.add(ctx.seq.end_date, 1)
      })

    [awa_row, bob_row] = Discipline.conduct_sheet(ctx.scope, ctx.cg, ctx.seq)

    assert awa_row.student.full_name == "Awa"
    assert awa_row.current == nil
    assert [%{type: :avertissement}] = awa_row.sanctions
    # 20 − 5/6 × 0.5 − 2 = 17.583… → 17.5
    assert Decimal.equal?(awa_row.suggestion.mark, Decimal.new("17.5"))

    assert bob_row.retards == 1
    # 20 − 0.25
    assert Decimal.equal?(bob_row.suggestion.mark, Decimal.new("19.75"))
  end

  test "a clean student is listed at 20 with no deductions", ctx do
    rows = Discipline.conduct_sheet(ctx.scope, ctx.cg, ctx.seq)

    assert Enum.all?(
             rows,
             &(Decimal.equal?(&1.suggestion.mark, 20) and &1.suggestion.deductions == [])
           )
  end

  test "the class is saved in one go; saving again replaces the marks", ctx do
    assert {:ok, 2} =
             Discipline.set_conduct_marks(ctx.scope, ctx.cg, ctx.seq, %{
               ctx.awa.id => "17,5",
               ctx.bob.id => "19.75"
             })

    assert {:ok, 1} =
             Discipline.set_conduct_marks(ctx.scope, ctx.cg, ctx.seq, %{
               ctx.awa.id => "16",
               ctx.bob.id => ""
             })

    [awa_row, bob_row] = Discipline.conduct_sheet(ctx.scope, ctx.cg, ctx.seq)
    assert Decimal.equal?(awa_row.current, 16)
    assert Decimal.equal?(bob_row.current, Decimal.new("19.75"))
  end

  test "one bad value saves nothing and names the student", ctx do
    assert {:error, {:invalid_value, id}} =
             Discipline.set_conduct_marks(ctx.scope, ctx.cg, ctx.seq, %{
               ctx.awa.id => "15",
               ctx.bob.id => "25"
             })

    assert id == ctx.bob.id

    assert {:error, {:invalid_value, _}} =
             Discipline.set_conduct_marks(ctx.scope, ctx.cg, ctx.seq, %{ctx.awa.id => "abc"})

    assert Enum.all?(Discipline.conduct_sheet(ctx.scope, ctx.cg, ctx.seq), &is_nil(&1.current))
  end

  test "a student of another class is refused", ctx do
    assert {:error, :not_in_class} =
             Discipline.set_conduct_marks(ctx.scope, ctx.cg, ctx.seq, %{ctx.zoe.id => "15"})
  end

  test "a plain teacher may not save", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    teacher = %{teacher | current_academic_year: ctx.year}

    assert_forbidden(
      Discipline.set_conduct_marks(teacher, ctx.cg, ctx.seq, %{ctx.awa.id => "15"})
    )
  end
end
