defmodule TeacherAssistant.Academics.FeesDataTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Enrollment}

  alias TeacherAssistant.Academics.{
    ClassFee,
    FeeAdjustment,
    FeeTranche,
    FeeType,
    Payment
  }

  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, year: year} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa A", sex: :f})
    %{scope: scope, year: year, cg: cg, e: e}
  end

  defp create(resource, action \\ :create, attrs, scope),
    do: resource |> Ash.Changeset.for_create(action, attrs, scope: scope) |> Ash.create()

  defp fee_type!(ctx, name, position \\ 1) do
    {:ok, t} =
      create(FeeType, %{academic_year_id: ctx.year.id, name: name, position: position}, ctx.scope)

    t
  end

  defp payment_attrs(ctx, seq),
    do: %{
      enrollment_id: ctx.e.id,
      academic_year_id: ctx.year.id,
      amount: 5_000,
      paid_on: ~D[2025-10-01],
      method: :cash,
      seq: seq,
      number: "R2025-#{String.pad_leading(to_string(seq), 6, "0")}",
      paid_to_date: 5_000,
      left_after: 0,
      student_name: "Awa A",
      class_label: "6e Q"
    }

  test "fee type names are unique per year regardless of case", ctx do
    fee_type!(ctx, "Frais exigibles")

    assert {:error, _} =
             create(
               FeeType,
               %{academic_year_id: ctx.year.id, name: " frais EXIGIBLES ", position: 2},
               ctx.scope
             )
  end

  test "a class fee is one amount per class and fee type (upsert)", ctx do
    t = fee_type!(ctx, "PTA")
    attrs = %{class_group_id: ctx.cg.id, fee_type_id: t.id, amount: 10_000}
    {:ok, a} = create(ClassFee, :set, attrs, ctx.scope)
    {:ok, b} = create(ClassFee, :set, %{attrs | amount: 12_000}, ctx.scope)
    assert a.id == b.id and b.amount == 12_000
    assert {:error, _} = create(ClassFee, :set, %{attrs | amount: -1}, ctx.scope)
  end

  test "a tranche percent is 1..100", ctx do
    base = %{
      academic_year_id: ctx.year.id,
      label: "1re tranche",
      due_date: ~D[2025-10-15],
      position: 0
    }

    assert {:ok, _} = create(FeeTranche, Map.put(base, :percent, 50), ctx.scope)
    assert {:error, _} = create(FeeTranche, Map.put(base, :percent, 0), ctx.scope)
    assert {:error, _} = create(FeeTranche, Map.put(base, :percent, 101), ctx.scope)
  end

  test "an adjustment is one per enrollment and fee type", ctx do
    pta = fee_type!(ctx, "PTA")
    fe = fee_type!(ctx, "Frais exigibles", 0)

    attrs = %{
      enrollment_id: ctx.e.id,
      fee_type_id: pta.id,
      amount: 5_000,
      reason: "Enfant du personnel"
    }

    {:ok, a} = create(FeeAdjustment, :set, attrs, ctx.scope)
    {:ok, b} = create(FeeAdjustment, :set, %{attrs | amount: 6_000}, ctx.scope)
    assert a.id == b.id
    {:ok, c} = create(FeeAdjustment, :set, %{attrs | fee_type_id: fe.id}, ctx.scope)
    refute c.id == a.id
  end

  test "a payment has no update or destroy action" do
    refute Ash.Resource.Info.action(Payment, :update)
    refute Ash.Resource.Info.action(Payment, :destroy)
  end

  test "cancel needs a reason and cannot run twice", ctx do
    {:ok, p} = create(Payment, payment_attrs(ctx, 1), ctx.scope)
    assert p.status == :valid

    cancel = fn p, reason ->
      p |> Ash.Changeset.for_update(:cancel, %{reason: reason}, scope: ctx.scope) |> Ash.update()
    end

    assert {:error, _} = cancel.(p, "  ")
    assert {:ok, c} = cancel.(p, "Erreur de montant")
    assert c.status == :cancelled and c.cancel_reason == "Erreur de montant"
    assert c.cancelled_by_user_id == ctx.scope.current_user.id and c.cancelled_at
    assert {:error, _} = cancel.(c, "Encore")
  end

  test "two payments of a year cannot share a seq", ctx do
    {:ok, _} = create(Payment, payment_attrs(ctx, 1), ctx.scope)
    assert {:error, _} = create(Payment, payment_attrs(ctx, 1), ctx.scope)
  end

  test "nothing fee-related is written in a closed year", ctx do
    t = fee_type!(ctx, "PTA")
    %{next: _} = TeacherFixtures.close_year!(ctx.scope, ctx.year)

    assert {:error, _} =
             create(
               FeeType,
               %{academic_year_id: ctx.year.id, name: "Info", position: 3},
               ctx.scope
             )

    assert {:error, _} =
             create(
               ClassFee,
               :set,
               %{class_group_id: ctx.cg.id, fee_type_id: t.id, amount: 1},
               ctx.scope
             )

    assert {:error, _} = create(Payment, payment_attrs(ctx, 1), ctx.scope)
  end

  test "a teacher cannot create a fee type, a class fee or a payment", ctx do
    t = fee_type!(ctx, "PTA")
    teacher = %{TeacherFixtures.member_scope_fixture(ctx.scope) | current_academic_year: ctx.year}

    assert {:error, %Ash.Error.Forbidden{}} =
             create(FeeType, %{academic_year_id: ctx.year.id, name: "X", position: 2}, teacher)

    assert {:error, %Ash.Error.Forbidden{}} =
             create(
               ClassFee,
               :set,
               %{class_group_id: ctx.cg.id, fee_type_id: t.id, amount: 1},
               teacher
             )

    assert {:error, %Ash.Error.Forbidden{}} = create(Payment, payment_attrs(ctx, 1), teacher)
  end

  test "an enrollment with a payment cannot be withdrawn (its receipts must survive)", ctx do
    {:ok, _} = create(Payment, payment_attrs(ctx, 1), ctx.scope)
    assert {:error, _} = Enrollment.withdraw(ctx.scope, ctx.e)
    assert {:ok, _} = Enrollment.fetch_owned_enrollment(ctx.scope, ctx.e.id)
  end
end
