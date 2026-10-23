defmodule TeacherAssistant.Academics.FeesSetupTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Enrollment, Fees}
  alias TeacherAssistant.Academics.{Payment, PaymentAllocation}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, year: year} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    {:ok, q} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, r} = Enrollment.create_class_group(scope, year, %{label: "6e R", level: "6ème"})

    {:ok, t} =
      Enrollment.create_class_group(scope, year, %{label: "Tle D", level: "Tle", serie: "D"})

    %{scope: scope, year: year, q: q, r: r, t: t}
  end

  defp names(types), do: Enum.map(types, & &1.name)

  defp defaults!(ctx) do
    {:ok, _} = Fees.create_default_fee_types(ctx.scope, ctx.year)
    [fe, pta] = Fees.list_fee_types(ctx.scope, ctx.year)
    {fe, pta}
  end

  # A payment written straight to the resources (record_payment comes in Task 4).
  defp pay!(scope, e, type, amount) do
    p =
      Payment
      |> paper_changeset(
        :create,
        %{
          enrollment_id: e.id,
          academic_year_id: e.academic_year_id,
          amount: amount,
          paid_on: ~D[2025-10-01],
          method: :cash,
          seq: System.unique_integer([:positive]),
          number: "R-test",
          paid_to_date: amount,
          left_after: 0,
          student_name: "x",
          class_label: "x"
        },
        scope: scope
      )
      |> Ash.create!()

    PaymentAllocation
    |> paper_changeset(
      :create,
      %{
        payment_id: p.id,
        fee_type_id: type.id,
        amount: amount,
        paid_to_date: amount,
        left_after: 0
      },
      scope: scope
    )
    |> Ash.create!()

    p
  end

  test "default types are Frais exigibles then PTA, once", ctx do
    {:ok, _} = Fees.create_default_fee_types(ctx.scope, ctx.year)
    {:ok, _} = Fees.create_default_fee_types(ctx.scope, ctx.year)
    assert names(Fees.list_fee_types(ctx.scope, ctx.year)) == ["Frais exigibles", "PTA"]
  end

  test "moving a type changes the payment order; the arrears type stays first", ctx do
    {_fe, pta} = defaults!(ctx)
    {:ok, info} = Fees.create_fee_type(ctx.scope, ctx.year, %{name: "Frais informatique"})

    assert names(Fees.list_fee_types(ctx.scope, ctx.year)) == [
             "Frais exigibles",
             "PTA",
             "Frais informatique"
           ]

    :ok = Fees.move_fee_type(ctx.scope, info, :up)

    assert names(Fees.list_fee_types(ctx.scope, ctx.year)) == [
             "Frais exigibles",
             "Frais informatique",
             "PTA"
           ]

    {:ok, _} = Fees.rename_fee_type(ctx.scope, pta, "APEE")
    assert "APEE" in names(Fees.list_fee_types(ctx.scope, ctx.year))
  end

  test "a type with an amount or a payment cannot be deactivated", ctx do
    {fe, pta} = defaults!(ctx)
    {:ok, _} = Fees.set_class_fee(ctx.scope, ctx.q, fe, 50_000)
    assert {:error, :in_use} = Fees.deactivate_fee_type(ctx.scope, fe)
    assert {:ok, %{active?: false}} = Fees.deactivate_fee_type(ctx.scope, pta)
    assert {:ok, %{active?: true}} = Fees.reactivate_fee_type(ctx.scope, pta)
  end

  test "set_level_fee sets every class of the same level and série", ctx do
    {fe, _} = defaults!(ctx)
    :ok = Fees.set_level_fee(ctx.scope, ctx.year, ctx.q, fe, 45_000)
    grid = Fees.class_fee_grid(ctx.scope, ctx.year)
    assert grid[{ctx.q.id, fe.id}] == 45_000
    assert grid[{ctx.r.id, fe.id}] == 45_000
    refute Map.has_key?(grid, {ctx.t.id, fe.id})
  end

  test "tranches are listed by due date and keep their percent", ctx do
    {:ok, _} =
      Fees.add_tranche(ctx.scope, ctx.year, %{
        label: "2e tranche",
        due_date: ~D[2026-01-15],
        percent: 100
      })

    {:ok, t1} =
      Fees.add_tranche(ctx.scope, ctx.year, %{
        label: "1re tranche",
        due_date: ~D[2025-10-15],
        percent: 40
      })

    assert Enum.map(Fees.list_tranches(ctx.scope, ctx.year), & &1.percent) == [40, 100]
    {:ok, _} = Fees.update_tranche(ctx.scope, t1, %{percent: 50})
    :ok = Fees.delete_tranche(ctx.scope, t1)
    assert [%{percent: 100}] = Fees.list_tranches(ctx.scope, ctx.year)
  end

  test "copy_previous_year copies types, amounts by matched class and shifted tranches, and lists unmatched classes",
       ctx do
    {fe, pta} = defaults!(ctx)
    {:ok, _} = Fees.set_class_fee(ctx.scope, ctx.q, fe, 50_000)
    {:ok, _} = Fees.set_class_fee(ctx.scope, ctx.q, pta, 10_000)

    {:ok, _} =
      Fees.add_tranche(ctx.scope, ctx.year, %{label: "1re", due_date: ~D[2025-10-15], percent: 40})

    %{next: next} = TeacherFixtures.close_year!(ctx.scope, ctx.year)
    scope = %{ctx.scope | current_academic_year: next}
    # "6ème Z" (made by close_year!) matches 6e Q by level; "1ère TI" has no match.
    {:ok, c} =
      Enrollment.create_class_group(scope, next, %{label: "1ère TI", level: "1ère", serie: "TI"})

    [z] = scope |> Enrollment.list_class_groups(next) |> Enum.filter(&(&1.label == "6ème Z"))

    assert {:ok, %{unmatched: ["1ère TI"]}} = Fees.copy_previous_year(scope, next)
    [fe2, pta2] = Fees.list_fee_types(scope, next)
    assert {fe2.name, pta2.name} == {"Frais exigibles", "PTA"}
    grid = Fees.class_fee_grid(scope, next)
    assert grid[{z.id, fe2.id}] == 50_000 and grid[{z.id, pta2.id}] == 10_000
    refute Map.has_key?(grid, {c.id, fe2.id})
    assert [%{due_date: ~D[2026-10-15], percent: 40}] = Fees.list_tranches(scope, next)
  end

  test "copy_previous_year refuses a year that already has types", ctx do
    defaults!(ctx)
    assert {:error, :not_empty} = Fees.copy_previous_year(ctx.scope, ctx.year)
  end

  test "arrears: candidates, carry once, the arrears type first", ctx do
    {fe, _pta} = defaults!(ctx)
    {:ok, _} = Fees.set_class_fee(ctx.scope, ctx.q, fe, 50_000)

    {:ok, %{enrollment: e1, student: s1}} =
      Enrollment.enroll_new(ctx.scope, ctx.q, %{full_name: "Awa A", sex: :f})

    {:ok, %{enrollment: _e2}} =
      Enrollment.enroll_new(ctx.scope, ctx.q, %{full_name: "Bel B", sex: :m})

    {:ok, %{enrollment: e3}} =
      Enrollment.enroll_new(ctx.scope, ctx.q, %{full_name: "Cam C", sex: :m})

    pay!(ctx.scope, e1, fe, 20_000)
    pay!(ctx.scope, e3, fe, 50_000)

    %{next: next} = TeacherFixtures.close_year!(ctx.scope, ctx.year)
    scope = %{ctx.scope | current_academic_year: next}
    [z] = scope |> Enrollment.list_class_groups(next) |> Enum.filter(&(&1.label == "6ème Z"))
    {:ok, ne1} = Enrollment.enroll_existing(scope, z, s1)

    candidates = Fees.arrears_candidates(scope, next)
    by_name = Map.new(candidates, &{&1.student.full_name, &1})
    assert by_name["Awa A"].amount == 30_000 and by_name["Awa A"].enrollment.id == ne1.id
    assert by_name["Bel B"].amount == 50_000 and by_name["Bel B"].enrollment == nil
    refute Map.has_key?(by_name, "Cam C")

    assert {:ok, 1} = Fees.carry_arrears(scope, next, [ne1.id, Ecto.UUID.generate()])

    assert [%{kind: :arrears, name: "Reliquat année précédente", position: 0}] =
             Fees.list_fee_types(scope, next)

    assert Fees.arrears_candidates(scope, next) |> Enum.map(& &1.student.full_name) == ["Bel B"]
    assert {:ok, 0} = Fees.carry_arrears(scope, next, [ne1.id])
  end

  test "an adjustment larger than the type's due is refused", ctx do
    {fe, pta} = defaults!(ctx)
    {:ok, _} = Fees.set_class_fee(ctx.scope, ctx.q, pta, 10_000)

    {:ok, %{enrollment: e}} =
      Enrollment.enroll_new(ctx.scope, ctx.q, %{full_name: "Awa A", sex: :f})

    assert {:error, :too_large} =
             Fees.set_adjustment(ctx.scope, e, pta, %{amount: 10_001, reason: "Exonéré"})

    assert {:ok, _} = Fees.set_adjustment(ctx.scope, e, pta, %{amount: 10_000, reason: "Exonéré"})
    assert {:error, :too_large} = Fees.set_adjustment(ctx.scope, e, fe, %{amount: 1, reason: "x"})
    assert :ok = Fees.clear_adjustment(ctx.scope, e, pta)
  end

  test "tranche percents must rise with their dates", ctx do
    {:ok, t1} =
      Fees.add_tranche(ctx.scope, ctx.year, %{label: "1re", due_date: ~D[2025-10-15], percent: 50})

    assert {:error, :not_rising} =
             Fees.add_tranche(ctx.scope, ctx.year, %{
               label: "2e",
               due_date: ~D[2026-01-15],
               percent: 40
             })

    assert {:error, :not_rising} =
             Fees.add_tranche(ctx.scope, ctx.year, %{
               label: "0",
               due_date: ~D[2025-09-15],
               percent: 60
             })

    {:ok, _} =
      Fees.add_tranche(ctx.scope, ctx.year, %{label: "2e", due_date: ~D[2026-01-15], percent: 100})

    assert {:error, :not_rising} = Fees.update_tranche(ctx.scope, t1, %{percent: 100})
  end
end
