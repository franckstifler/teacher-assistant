defmodule TeacherAssistant.FeeControlWarningsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Enrollment, FeeControl, Fees, FeesFixtures, TeacherFixtures}

  @today ~D[2025-09-15]
  @pay_by ~D[2025-09-22]

  # Awa owes 40 % of 50 000 + 10 000 = 24 000 today, all toward « Frais exigibles ».
  setup do
    ctx = FeesFixtures.fees_school_fixture()

    {:ok, _} =
      Fees.add_tranche(ctx.scope, ctx.year, %{
        label: "Inscription",
        due_date: ~D[2025-09-01],
        percent: 40
      })

    ctx
  end

  test "one warning per behind student, numbered, lines frozen", ctx do
    assert {:ok, [w]} = FeeControl.issue_warnings(ctx.scope, [ctx.e], @pay_by)
    assert w.number == "V#{ctx.year.start_date.year}-000001"
    assert [%{name: "Frais exigibles", amount: 24_000}] = w.lines
    assert w.total == 24_000 and w.pay_by == @pay_by and w.issued_on == @today

    {:ok, _} = Fees.set_class_fee(ctx.scope, ctx.cg, ctx.fe, 80_000)
    assert [%{lines: [%{amount: 24_000}]}] = FeeControl.list_warnings(ctx.scope, ctx.e)
  end

  test "students not behind are skipped; none behind gives :nothing_to_warn", ctx do
    {:ok, %{enrollment: e2}} =
      Enrollment.enroll_new(ctx.scope, ctx.cg, %{full_name: "Ben B", sex: :m})

    {:ok, _} = Fees.record_payment(ctx.scope, e2, FeesFixtures.cash(24_000))
    assert {:ok, [w]} = FeeControl.issue_warnings(ctx.scope, [ctx.e, e2], @pay_by)
    assert w.enrollment_id == ctx.e.id

    assert {:error, :nothing_to_warn} = FeeControl.issue_warnings(ctx.scope, [e2], @pay_by)
  end

  test "lines add up to total and follow payment order", ctx do
    {:ok, _} = Fees.record_payment(ctx.scope, ctx.e, FeesFixtures.cash(15_000))
    # Raise what is due today: 45 % of 60 000 = 27 000; 15 000 paid on Frais exigibles.
    {:ok, _} =
      Fees.add_tranche(ctx.scope, ctx.year, %{label: "T", due_date: ~D[2025-09-10], percent: 45})

    {:ok, [w]} = FeeControl.issue_warnings(ctx.scope, [ctx.e], @pay_by)

    assert Enum.map(w.lines, &{&1.name, &1.amount}) == [{"Frais exigibles", 12_000}]
    assert w.total == Enum.sum(Enum.map(w.lines, & &1.amount))
  end

  test "a past pay_by is refused", ctx do
    assert {:error, :invalid_pay_by} =
             FeeControl.issue_warnings(ctx.scope, [ctx.e], ~D[2025-09-14])
  end

  test "only the fees axis can issue", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    assert {:error, _} = FeeControl.issue_warnings(teacher, [ctx.e], @pay_by)
  end

  test "cancel and print data", ctx do
    {:ok, [w]} = FeeControl.issue_warnings(ctx.scope, [ctx.e], @pay_by)

    assert {:ok, [%{warning: %{id: id}, school: %{name: _}}]} =
             FeeControl.warnings(ctx.scope, [w.id])

    assert id == w.id
    assert {:error, :reason_required} = FeeControl.cancel_warning(ctx.scope, w, "")
    assert {:ok, %{status: :cancelled}} = FeeControl.cancel_warning(ctx.scope, w, "Erreur")
    assert FeeControl.default_pay_by() == ~D[2025-09-22]
  end

  test "a warning and its cancellation carry the operator (minors)", ctx do
    op = TeacherFixtures.admin_user_fixture()
    imp = impersonating(ctx.scope, op)

    {:ok, [w]} = FeeControl.issue_warnings(imp, [ctx.e], @pay_by)
    assert w.operator_user_id == op.id
    {:ok, cancelled} = FeeControl.cancel_warning(imp, w, "erreur")
    assert cancelled.cancelled_operator_user_id == op.id
  end
end
