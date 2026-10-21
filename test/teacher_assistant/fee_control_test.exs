defmodule TeacherAssistant.FeeControlTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Enrollment, FeeControl, Fees, FeesFixtures, TeacherFixtures}
  alias TeacherAssistant.Academics.ReturnNote

  @today ~D[2025-09-15]

  # The fixture's first tranche is due 2025-10-15; add one already due (40 %), so Awa
  # (60 000 due, nothing paid) owes 24 000 today.
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

  defp note!(ctx, valid_until, issued_on \\ @today) do
    ReturnNote
    |> Ash.Changeset.for_create(
      :create,
      %{
        enrollment_id: ctx.e.id,
        academic_year_id: ctx.year.id,
        seq: System.unique_integer([:positive]),
        number: "A-test",
        reason: :promise,
        issued_on: issued_on,
        valid_until: valid_until,
        student_name: "Awa A",
        class_label: "6e Q"
      },
      scope: ctx.scope
    )
    |> Ash.create!()
  end

  test "behind without a note must leave, with what they owe", ctx do
    control = FeeControl.class_control(ctx.scope, ctx.cg, @today)
    assert [%{owed: 24_000, note: nil, sent_out?: false} = row] = control.must_leave
    assert row.student.full_name == "Awa A"
    assert control.allowed == []
    assert control.tranche.label == "Inscription"
  end

  test "a valid note moves a late student to allowed, with the note", ctx do
    note = note!(ctx, ~D[2025-09-30])
    control = FeeControl.class_control(ctx.scope, ctx.cg, @today)
    assert control.must_leave == []
    assert [%{note: %{id: id}}] = control.allowed
    assert id == note.id
  end

  test "an expired note puts them back in must_leave", ctx do
    note!(ctx, ~D[2025-09-10], ~D[2025-09-05])
    control = FeeControl.class_control(ctx.scope, ctx.cg, @today)
    assert [_] = control.must_leave
  end

  test "students up to date are only counted", ctx do
    {:ok, %{enrollment: e2}} =
      Enrollment.enroll_new(ctx.scope, ctx.cg, %{full_name: "Ben B", sex: :m})

    {:ok, _} = Fees.record_payment(ctx.scope, e2, FeesFixtures.cash(24_000))
    control = FeeControl.class_control(ctx.scope, ctx.cg, @today)
    assert length(control.must_leave) == 1
    assert control.up_to_date == 1
  end

  test "no tranche due: nobody listed, everybody up to date", ctx do
    control = FeeControl.class_control(ctx.scope, ctx.cg, ~D[2025-08-31])
    assert control.must_leave == [] and control.allowed == []
    assert control.up_to_date == 1
    assert control.tranche == nil
  end

  test "record_send_out is idempotent and undo removes it", ctx do
    assert {:ok, _} = FeeControl.record_send_out(ctx.scope, ctx.e, @today)
    assert {:ok, _} = FeeControl.record_send_out(ctx.scope, ctx.e, @today)
    assert FeeControl.sent_home_ids(ctx.scope, [ctx.e.id], @today) == MapSet.new([ctx.e.id])
    assert [%{sent_out?: true}] = FeeControl.class_control(ctx.scope, ctx.cg, @today).must_leave

    assert :ok = FeeControl.undo_send_out(ctx.scope, ctx.e, @today)
    assert FeeControl.sent_home_ids(ctx.scope, [ctx.e.id], @today) == MapSet.new()
  end

  test "a teacher cannot record a send-out but sees it", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})
    assert {:error, _} = FeeControl.record_send_out(teacher, ctx.e, @today)
    {:ok, _} = FeeControl.record_send_out(ctx.scope, ctx.e, @today)
    assert FeeControl.sent_home_ids(teacher, [ctx.e.id], @today) == MapSet.new([ctx.e.id])
  end

  test "a payment that brings the student up to date lifts today's send-out", ctx do
    {:ok, _} = FeeControl.record_send_out(ctx.scope, ctx.e, @today)
    {:ok, _} = Fees.record_payment(ctx.scope, ctx.e, FeesFixtures.cash(24_000))
    assert FeeControl.sent_home_ids(ctx.scope, [ctx.e.id], @today) == MapSet.new()
  end

  test "a partial payment that leaves them behind keeps the send-out", ctx do
    {:ok, _} = FeeControl.record_send_out(ctx.scope, ctx.e, @today)
    {:ok, _} = Fees.record_payment(ctx.scope, ctx.e, FeesFixtures.cash(10_000))
    assert FeeControl.sent_home_ids(ctx.scope, [ctx.e.id], @today) == MapSet.new([ctx.e.id])
  end
end
