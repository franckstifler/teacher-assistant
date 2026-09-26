defmodule TeacherAssistant.Authorization.RevocationTest do
  @moduledoc "A deactivated member keeps their scope (an open LiveView) but is refused on the next call."
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Accounts, Assessment, Curriculum, Enrollment, Fees, Organization}

  setup do
    %{year: year, scope: head} = setup_complete_school_fixture()
    %{teaching_context: tc, class_group: cg, scope: owner} = school_teacher_fixture(head)
    {:ok, cg} = Enrollment.set_form_master(head, cg, owner.current_user.id)
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(head, cg, %{full_name: "Awa", sex: :f})
    [seq | _] = Organization.list_sequences(head, year)
    {:ok, plan} = Curriculum.create_progression_plan(owner, tc, %{title: "Plan"})

    {:ok, _} =
      Fees.record_payment(head, e, %{amount: 1_000, paid_on: ~D[2025-10-01], method: :cash})

    {:ok, m} = Accounts.fetch_school_membership(head, owner.current_user)
    {:ok, _} = Accounts.deactivate_member(head, m)
    %{head: head, owner: owner, tc: tc, cg: cg, seq: seq, plan: plan, e: e}
  end

  test "a revoked owner can no longer write their own teaching data", ctx do
    assert_forbidden(Assessment.create_assessment(ctx.owner, ctx.tc, ctx.seq, %{label: "D1"}))
    assert_forbidden(Curriculum.create_module(ctx.owner, ctx.plan, %{title: "M"}))
  end

  test "a revoked form master can no longer withdraw or read fees", ctx do
    assert_forbidden(Enrollment.withdraw(ctx.owner, ctx.e))
    assert Fees.list_payments(ctx.owner, ctx.e) == []
  end

  test "a revoked member's read-shaped actions return empty instead of crashing", ctx do
    [period | _] = TeacherAssistant.Attendance.list_periods(ctx.head)

    assert %{students: [], teaching_context: nil} =
             TeacherAssistant.Attendance.period_roll(ctx.owner, ctx.cg, period, ~D[2025-09-15])
  end
end
