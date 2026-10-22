defmodule TeacherAssistantWeb.ReceiptVerificationTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.FeesFixtures

  alias TeacherAssistant.Fees
  alias TeacherAssistantWeb.ReceiptVerification, as: V

  test "a token round-trips to the payment; a changed character is :invalid" do
    ctx = fees_school_fixture()
    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(20_000))
    token = V.token(p)
    assert String.length(token) == 64
    assert {:valid, %{number: "R2025-000001"}} = V.verify(token)

    <<first::binary-size(1), rest::binary>> = token
    forged = if(first == "A", do: "B", else: "A") <> rest
    assert V.verify(forged) == :invalid
    assert V.verify("short") == :invalid
  end

  test "wrong codes for one number are capped; other numbers are not affected" do
    for _ <- 1..20, do: assert(V.lookup("R2025-990002", "zzzzzz") == :invalid)
    assert V.lookup(" r2025-990002 ", "zzzzzz") == :throttled
    assert V.lookup("R2025-990003", "zzzzzz") == :invalid
  end

  test "lookup needs the right number and code; school A's code never opens school B's receipt" do
    a = fees_school_fixture()
    b = fees_school_fixture()
    {:ok, pa} = Fees.record_payment(a.scope, a.e, cash(1_000))
    {:ok, pb} = Fees.record_payment(b.scope, b.e, cash(2_000))
    assert pa.number == pb.number

    assert {:valid, %{amount: 1_000}} = V.lookup(pa.number, V.code(V.token(pa)))
    assert {:valid, %{amount: 2_000}} = V.lookup(pb.number, V.code(V.token(pb)))
    assert V.lookup(pa.number, "zzzzzz") == :invalid
    assert V.lookup("R1999-000001", V.code(V.token(pa))) == :invalid
  end

  test "the typed code ignores case, spaces and O/0 or I/L/1 mix-ups, and is 6 unambiguous characters" do
    ctx = fees_school_fixture()
    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(1_000))
    code = V.code(V.token(p))
    assert code =~ ~r/^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{6}$/

    sloppy =
      code
      |> String.downcase()
      |> String.replace("0", "o")
      |> String.replace("1", "l")

    assert {:valid, _} = V.lookup(" " <> String.downcase(p.number) <> " ", " " <> sloppy)
  end

  describe "Fees 2 papers" do
    setup do
      ctx = fees_school_fixture()

      {:ok, _} =
        Fees.add_tranche(ctx.scope, ctx.year, %{label: "I", due_date: ~D[2025-09-01], percent: 40})

      ctx
    end

    test "a note token verifies; a receipt token does not verify as a note", ctx do
      {:ok, note} =
        TeacherAssistant.FeeControl.issue_note(ctx.scope, ctx.e, %{
          reason: :promise,
          valid_until: ~D[2025-09-30]
        })

      assert {:valid, %{kind: :note, number: "A2025-000001", reason: :promise}} =
               V.verify(:note, V.token(:note, note))

      {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(1_000))
      assert V.verify(:note, V.token(p)) == :invalid
      assert V.code(V.token(:note, note)) != V.code(V.token(%{note | id: note.id}))
    end

    test "typed A-number + code finds the note, case-insensitive", ctx do
      {:ok, note} =
        TeacherAssistant.FeeControl.issue_note(ctx.scope, ctx.e, %{reason: :exemption})

      code = V.code(V.token(:note, note))

      assert {:valid, %{kind: :note}} =
               V.lookup(String.downcase(note.number), String.downcase(code))

      assert V.lookup(note.number, "000000") == :invalid
    end

    test "a warning verifies with its lines and total; typed V-number works", ctx do
      {:ok, [w]} =
        TeacherAssistant.FeeControl.issue_warnings(ctx.scope, [ctx.e], ~D[2025-09-22])

      assert {:valid, %{kind: :warning, total: 24_000, lines: [%{amount: 24_000}]}} =
               V.verify(:warning, V.token(:warning, w))

      assert {:valid, %{kind: :warning}} = V.lookup(w.number, V.code(V.token(:warning, w)))
    end
  end
end
