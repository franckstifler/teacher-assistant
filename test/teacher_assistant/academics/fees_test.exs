defmodule TeacherAssistant.Academics.FeesTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.FeesFixtures

  alias TeacherAssistant.{Enrollment, Fees}
  alias TeacherAssistant.TeacherFixtures

  setup do
    fees_school_fixture()
  end

  defp split(payment), do: Enum.map(payment.allocations, &{&1.fee_type.name, &1.amount})

  test "a payment is numbered R<year>-000001, then 000002", ctx do
    {:ok, p1} = Fees.record_payment(ctx.scope, ctx.e, cash(1_000))
    {:ok, p2} = Fees.record_payment(ctx.scope, ctx.e, cash(1_000))
    assert {p1.number, p2.number} == {"R2025-000001", "R2025-000002"}
    assert p1.recorded_by_user_id == ctx.scope.current_user.id
  end

  test "20_000 on a fresh student goes to Frais exigibles; the receipt freezes paid 20_000, left 40_000",
       ctx do
    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(20_000))
    assert split(p) == [{"Frais exigibles", 20_000}]
    assert {p.paid_to_date, p.left_after} == {20_000, 40_000}
    [a] = p.allocations
    assert {a.paid_to_date, a.left_after} == {20_000, 30_000}

    {:ok, p2} = Fees.record_payment(ctx.scope, ctx.e, cash(35_000))
    assert split(p2) == [{"Frais exigibles", 30_000}, {"PTA", 5_000}]
    assert {p2.paid_to_date, p2.left_after} == {55_000, 5_000}
  end

  test "the frozen figures do not change when the class amount changes later", ctx do
    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(20_000))
    {:ok, _} = Fees.set_class_fee(ctx.scope, ctx.cg, ctx.fe, 70_000)
    {:ok, again} = Fees.get_payment(ctx.scope, p.id)
    assert {again.paid_to_date, again.left_after} == {20_000, 40_000}
    assert Fees.student_fees(ctx.scope, ctx.e).left == 60_000
  end

  test "a payment beyond the total is accepted and shows Trop-perçu (negative left)", ctx do
    {:ok, _} = Fees.record_payment(ctx.scope, ctx.e, cash(60_000))
    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(5_000))
    assert split(p) == [{"PTA", 5_000}]
    assert p.left_after == -5_000
    assert Fees.student_fees(ctx.scope, ctx.e).left == -5_000
  end

  test "a cancelled payment stops counting; later payments keep their split", ctx do
    {:ok, p1} = Fees.record_payment(ctx.scope, ctx.e, cash(50_000))
    {:ok, p2} = Fees.record_payment(ctx.scope, ctx.e, cash(5_000))
    assert split(p2) == [{"PTA", 5_000}]
    {:ok, c} = Fees.cancel_payment(ctx.scope, p1, "Mauvais élève")
    assert c.status == :cancelled
    assert Fees.student_fees(ctx.scope, ctx.e).total_paid == 5_000
    {:ok, p2} = Fees.get_payment(ctx.scope, p2.id)
    assert split(p2) == [{"PTA", 5_000}]
  end

  test "cancel needs a reason", ctx do
    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(1_000))
    assert {:error, :reason_required} = Fees.cancel_payment(ctx.scope, p, "  ")
  end

  test "amount, method and reference are checked", ctx do
    assert {:error, :invalid_amount} = Fees.record_payment(ctx.scope, ctx.e, cash(0))

    assert {:error, :invalid_method} =
             Fees.record_payment(ctx.scope, ctx.e, %{cash(1) | method: :card})

    assert {:error, :reference_required} =
             Fees.record_payment(ctx.scope, ctx.e, %{cash(1_000) | method: :mobile_money})

    assert {:ok, %{reference: "MP2510"}} =
             Fees.record_payment(
               ctx.scope,
               ctx.e,
               Map.merge(cash(1_000), %{method: :mobile_money, reference: "MP2510"})
             )
  end

  test "a class without amounts: the money lands on the last type", ctx do
    {:ok, other} =
      Enrollment.create_class_group(ctx.scope, ctx.year, %{label: "6e R", level: "6ème"})

    {:ok, %{enrollment: e}} =
      Enrollment.enroll_new(ctx.scope, other, %{full_name: "Bel B", sex: :m})

    assert {:ok, p} = Fees.record_payment(ctx.scope, e, cash(1_000))
    assert p.left_after == -1_000
  end

  test "class balances and recovery: expected, to date, collected, rates, behind count", ctx do
    {:ok, %{enrollment: e2}} =
      Enrollment.enroll_new(ctx.scope, ctx.cg, %{full_name: "Bel B", sex: :m})

    {:ok, _} = Fees.record_payment(ctx.scope, ctx.e, cash(30_000))
    on = ~D[2025-11-01]

    balances = Fees.class_balances(ctx.scope, ctx.cg, on)
    assert balances[ctx.e.id].status == :on_track
    assert balances[e2.id].status == :behind

    %{school: school, classes: classes} = Fees.recovery(ctx.scope, ctx.year, on)
    row = Enum.find(classes, &(&1.class_group.id == ctx.cg.id))

    assert row.recovery == %{
             students: 2,
             expected: 120_000,
             expected_to_date: 60_000,
             collected: 30_000,
             rate: 25,
             rate_to_date: 50,
             behind: 1
           }

    assert school.collected == 30_000
  end

  test "arrears are paid before Frais exigibles", ctx do
    %{next: next} = TeacherFixtures.close_year!(ctx.scope, ctx.year)
    scope = %{ctx.scope | current_academic_year: next}
    [z] = scope |> Enrollment.list_class_groups(next) |> Enum.filter(&(&1.label == "6ème Z"))
    {:ok, ne} = Enrollment.enroll_existing(scope, z, ctx.student)
    {:ok, _} = Fees.create_default_fee_types(scope, next)
    [fe | _] = Fees.list_fee_types(scope, next)
    {:ok, _} = Fees.set_class_fee(scope, z, fe, 50_000)
    {:ok, 1} = Fees.carry_arrears(scope, next, [ne.id])

    {:ok, p} = Fees.record_payment(scope, ne, cash(70_000, ~D[2026-10-01]))
    assert split(p) == [{"Reliquat année précédente", 60_000}, {"Frais exigibles", 10_000}]
    assert p.number == "R2026-000001"
  end

  test "carrying arrears again carries nothing twice; a refused carry is an error", ctx do
    %{next: next} = TeacherFixtures.close_year!(ctx.scope, ctx.year)
    scope = %{ctx.scope | current_academic_year: next}
    [z] = scope |> Enrollment.list_class_groups(next) |> Enum.filter(&(&1.label == "6ème Z"))
    {:ok, ne} = Enrollment.enroll_existing(scope, z, ctx.student)

    {:ok, 1} = Fees.carry_arrears(scope, next, [ne.id])
    assert {:ok, 0} = Fees.carry_arrears(scope, next, [ne.id])
    assert [_] = Enum.filter(Fees.list_fee_types(scope, next), &(&1.kind == :arrears))

    # A member without the fees axis gets an error back, not a crash.
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    teacher = %{teacher | current_academic_year: next}
    assert {:error, %Ash.Error.Forbidden{}} = Fees.carry_arrears(teacher, next, [ne.id])
  end

  test "verification shows the receipt without phone numbers; cancelled shows :cancelled; unknown :invalid",
       ctx do
    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(20_000))
    ws = ctx.scope.current_workspace.id

    assert {:valid, v} = Fees.verification(ws, p.id)
    assert v.number == "R2025-000001" and v.student_name == "Awa A" and v.class_label == "6e Q"
    assert v.amount == 20_000 and v.paid_to_date == 20_000 and v.left_after == 40_000
    assert v.allocations == [%{name: "Frais exigibles", amount: 20_000}]
    refute Map.has_key?(v, :guardians) or Map.has_key?(v, :phone)

    {:ok, _} = Fees.cancel_payment(ctx.scope, p, "Erreur")
    assert {:cancelled, _} = Fees.verification(ws, p.id)
    assert :invalid = Fees.verification(ws, Ecto.UUID.generate())
    assert :invalid = Fees.verification(Ecto.UUID.generate(), p.id)
  end

  test "find_by_number returns every school's payment with that number", ctx do
    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(1_000))
    other = fees_school_fixture()
    {:ok, q} = Fees.record_payment(other.scope, other.e, cash(1_000))

    assert Enum.sort(Fees.find_by_number("R2025-000001")) ==
             Enum.sort([
               {ctx.scope.current_workspace.id, p.id},
               {other.scope.current_workspace.id, q.id}
             ])
  end

  test "a payment in a closed year is refused", ctx do
    TeacherFixtures.close_year!(ctx.scope, ctx.year)
    assert {:error, _} = Fees.record_payment(ctx.scope, ctx.e, cash(1_000))
  end

  test "a school without any fee type cannot record a payment" do
    %{scope: scope, year: year} = TeacherFixtures.setup_complete_school_fixture()
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa A", sex: :f})
    assert {:error, :no_fee_types} = Fees.record_payment(scope, e, cash(1_000))
  end

  test "the receipt keeps the student's name and class of the day it was issued", ctx do
    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(1_000))

    {:ok, other} =
      Enrollment.create_class_group(ctx.scope, ctx.year, %{label: "6e R", level: "6ème"})

    {:ok, _} = Enrollment.transfer(ctx.scope, ctx.e, other)

    assert {:valid, %{class_label: "6e Q", student_name: "Awa A"}} =
             Fees.verification(ctx.scope.current_workspace.id, p.id)

    assert {:ok, %{class_label: "6e Q"}} = Fees.receipt(ctx.scope, p.id)
  end

  test "removing a reduction in a closed year returns an error instead of crashing", ctx do
    {:ok, _} = Fees.set_adjustment(ctx.scope, ctx.e, ctx.pta, %{amount: 1_000, reason: "x"})
    TeacherFixtures.close_year!(ctx.scope, ctx.year)
    assert {:error, _} = Fees.clear_adjustment(ctx.scope, ctx.e, ctx.pta)
  end
end
