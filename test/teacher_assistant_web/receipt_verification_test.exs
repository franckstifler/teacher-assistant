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
end
