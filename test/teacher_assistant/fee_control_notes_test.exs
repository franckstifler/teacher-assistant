defmodule TeacherAssistant.FeeControlNotesTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{FeeControl, Fees, FeesFixtures}

  @today ~D[2025-09-15]

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

  defp promise(date), do: %{reason: :promise, valid_until: date}

  test "numbers run A<year>-000001, A…-000002 per school and year", ctx do
    {:ok, n1} = FeeControl.issue_note(ctx.scope, ctx.e, promise(~D[2025-09-30]))
    {:ok, n2} = FeeControl.issue_note(ctx.scope, ctx.e, promise(~D[2025-09-30]))
    assert n1.number == "A#{ctx.year.start_date.year}-000001"
    assert n2.number == "A#{ctx.year.start_date.year}-000002"
    assert n1.student_name == "Awa A" and n1.class_label == "6e Q"
    assert n1.issued_on == @today
  end

  test "a promise without a date is refused; a past date is refused", ctx do
    assert {:error, :invalid_valid_until} =
             FeeControl.issue_note(ctx.scope, ctx.e, %{reason: :promise, valid_until: nil})

    assert {:error, :invalid_valid_until} =
             FeeControl.issue_note(ctx.scope, ctx.e, promise(~D[2025-09-14]))
  end

  test "payment and exemption default their valid_until", ctx do
    {:ok, paid} = FeeControl.issue_note(ctx.scope, ctx.e, %{reason: :payment})
    # The next tranche after today in the fixture is due 2025-10-15.
    assert paid.valid_until == ~D[2025-10-15]

    {:ok, exempt} = FeeControl.issue_note(ctx.scope, ctx.e, %{reason: :exemption})
    assert exempt.valid_until == ctx.year.end_date
  end

  test "issuing a note lifts today's send-out", ctx do
    {:ok, _} = FeeControl.record_send_out(ctx.scope, ctx.e, @today)
    {:ok, _} = FeeControl.issue_note(ctx.scope, ctx.e, promise(~D[2025-09-30]))
    assert FeeControl.sent_home_ids(ctx.scope, [ctx.e.id], @today) == MapSet.new()
  end

  test "a cancelled note no longer allows the student", ctx do
    {:ok, note} = FeeControl.issue_note(ctx.scope, ctx.e, promise(~D[2025-09-30]))
    assert [_] = FeeControl.class_control(ctx.scope, ctx.cg, @today).allowed

    assert {:error, :reason_required} = FeeControl.cancel_note(ctx.scope, note, " ")
    assert {:ok, %{status: :cancelled}} = FeeControl.cancel_note(ctx.scope, note, "Erreur")
    assert [_] = FeeControl.class_control(ctx.scope, ctx.cg, @today).must_leave
  end

  test "list_notes is newest first and note/2 gives the print data", ctx do
    {:ok, n1} = FeeControl.issue_note(ctx.scope, ctx.e, promise(~D[2025-09-30]))
    {:ok, n2} = FeeControl.issue_note(ctx.scope, ctx.e, %{reason: :exemption})
    assert Enum.map(FeeControl.list_notes(ctx.scope, ctx.e), & &1.id) == [n2.id, n1.id]

    assert {:ok, %{note: %{id: id}, school: %{name: _}, issued_by_name: _}} =
             FeeControl.note(ctx.scope, n1.id)

    assert id == n1.id
  end

  test "receipt numbering is unchanged", ctx do
    {:ok, p1} = Fees.record_payment(ctx.scope, ctx.e, FeesFixtures.cash(1_000))
    {:ok, p2} = Fees.record_payment(ctx.scope, ctx.e, FeesFixtures.cash(1_000))
    assert p1.number == "R#{ctx.year.start_date.year}-000001"
    assert p2.number == "R#{ctx.year.start_date.year}-000002"
  end
end
