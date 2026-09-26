defmodule TeacherAssistant.Authorization.FeesTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Enrollment, Fees, Scope}
  alias TeacherAssistant.Academics.FeeAdjustment

  setup do
    %{workspace: ws, year: year, scope: head} = setup_complete_school_fixture()
    [cg | _] = Enrollment.list_class_groups(head, year)
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(head, cg, %{full_name: "Awa", sex: :f})
    bursar = member_scope_fixture(head, %{roles: [:bursar]})
    fm = member_scope_fixture(head, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(head, cg, fm.current_user.id)
    teacher = member_scope_fixture(head, %{roles: [:teacher]})
    %{ws: ws, head: head, bursar: bursar, fm: fm, teacher: teacher, cg: cg, e: e}
  end

  defp payment, do: %{amount: 5_000, paid_on: ~D[2025-10-01], method: :cash}

  test "the fees axis records payments; form masters and teachers cannot", ctx do
    assert {:ok, _} = Fees.record_payment(ctx.bursar, ctx.e, payment())
    assert_forbidden(Fees.record_payment(ctx.fm, ctx.e, payment()))
    assert_forbidden(Fees.record_payment(ctx.teacher, ctx.e, payment()))
    assert_forbidden(Fees.record_payment(%Scope{current_workspace: ctx.ws}, ctx.e, payment()))
  end

  test "payments are readable by the fees axis and the class's form master only", ctx do
    {:ok, _} = Fees.record_payment(ctx.bursar, ctx.e, payment())
    assert Fees.list_payments(ctx.bursar, ctx.e) != []
    assert Fees.list_payments(ctx.fm, ctx.e) != []
    assert Fees.list_payments(ctx.teacher, ctx.e) == []
  end

  test "an adjustment must be a positive discount", ctx do
    assert {:error, :invalid_amount} = Fees.set_adjustment(ctx.bursar, ctx.e, %{amount: 0})
    assert {:error, :invalid_amount} = Fees.set_adjustment(ctx.bursar, ctx.e, %{amount: -500})
    assert {:error, :invalid_amount} = Fees.set_adjustment(ctx.bursar, ctx.e, %{amount: nil})
    assert {:ok, adj} = Fees.set_adjustment(ctx.bursar, ctx.e, %{amount: 2_000, reason: "Bourse"})
    assert adj.amount == 2_000
  end

  test "the database rejects a non-positive adjustment", ctx do
    assert {:error, %Ash.Error.Invalid{}} =
             FeeAdjustment
             |> Ash.Changeset.for_create(:set, %{amount: -1, enrollment_id: ctx.e.id},
               scope: ctx.bursar
             )
             |> Ash.create()
  end

  test "can_manage_fees? follows the axis", ctx do
    assert Fees.can_manage_fees?(ctx.bursar)
    refute Fees.can_manage_fees?(ctx.fm)
  end
end
