defmodule TeacherAssistant.Academics.TypedAbsenceTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics.TypedAbsence
  alias TeacherAssistant.{Enrollment, Organization, TeacherFixtures}

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
    [term | _] = Organization.list_terms(scope, year)
    [seq | _] = term.sequences
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: e}] = Enrollment.list_roster(scope, cg)

    %{scope: scope, year: year, term: term, seq: seq, cg: cg, e: e}
  end

  defp set_seq(scope, e, seq, hours) do
    TypedAbsence
    |> Ash.Changeset.for_create(
      :set_for_sequence,
      %{enrollment_id: e.id, sequence_id: seq.id, hours: hours},
      scope: scope
    )
    |> Ash.create()
  end

  defp rows(scope),
    do: TypedAbsence |> Ash.Query.for_read(:read, %{}, scope: scope) |> Ash.read!()

  test "a conduct manager sets and re-sets a séquence figure", ctx do
    sg = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:discipline_master]})

    assert {:ok, _} = set_seq(sg, ctx.e, ctx.seq, Decimal.new(2))
    assert {:ok, row} = set_seq(sg, ctx.e, ctx.seq, Decimal.new("3.5"))
    assert row.recorded_by_user_id == sg.current_user.id
    assert [%{hours: hours}] = rows(sg)
    assert Decimal.equal?(hours, Decimal.new("3.5"))
  end

  test "the form master sets a figure for their class", ctx do
    fm = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(ctx.scope, ctx.cg, fm.current_user.id)

    assert {:ok, _} = set_seq(fm, ctx.e, ctx.seq, Decimal.new(1))
    assert [_] = rows(fm)
  end

  test "form master of another class is forbidden", ctx do
    {:ok, other} =
      Enrollment.create_class_group(ctx.scope, ctx.year, %{label: "6e B", level: "6ème"})

    fm = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(ctx.scope, other, fm.current_user.id)
    {:ok, _} = set_seq(ctx.scope, ctx.e, ctx.seq, Decimal.new(1))

    assert {:error, %Ash.Error.Forbidden{}} = set_seq(fm, ctx.e, ctx.seq, Decimal.new(4))
    assert rows(fm) == []
  end

  test "refuses negative hours", ctx do
    assert {:error, _} = set_seq(ctx.scope, ctx.e, ctx.seq, Decimal.new(-1))
  end

  test "refuses a row with both sequence and term", ctx do
    assert {:error, _} =
             TypedAbsence
             |> Ash.Changeset.for_create(
               :set_for_sequence,
               %{enrollment_id: ctx.e.id, sequence_id: ctx.seq.id, hours: Decimal.new(1)},
               scope: ctx.scope
             )
             |> Ash.Changeset.force_change_attribute(:term_id, ctx.term.id)
             |> Ash.create()
  end

  test "a trimester figure sits beside a séquence figure", ctx do
    assert {:ok, _} = set_seq(ctx.scope, ctx.e, ctx.seq, Decimal.new(1))

    assert {:ok, _} =
             TypedAbsence
             |> Ash.Changeset.for_create(
               :set_for_term,
               %{enrollment_id: ctx.e.id, term_id: ctx.term.id, hours: Decimal.new(5)},
               scope: ctx.scope
             )
             |> Ash.create()

    assert length(rows(ctx.scope)) == 2
  end

  test "refuses a closed year", ctx do
    TeacherFixtures.close_year!(ctx.scope, ctx.year)
    assert {:error, _} = set_seq(ctx.scope, ctx.e, ctx.seq, Decimal.new(1))
  end
end
