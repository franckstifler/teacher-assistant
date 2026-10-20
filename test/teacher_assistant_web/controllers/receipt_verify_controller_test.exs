defmodule TeacherAssistantWeb.ReceiptVerifyControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  import TeacherAssistant.FeesFixtures

  alias TeacherAssistant.{Enrollment, Fees}
  alias TeacherAssistantWeb.ReceiptVerification

  setup do
    ctx = fees_school_fixture()

    {:ok, _} =
      Enrollment.add_guardian(ctx.scope, ctx.student, %{
        full_name: "Mère A",
        relationship: :mere,
        phone: "677123456"
      })

    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(20_000))
    Map.put(ctx, :payment, p)
  end

  test "a valid token shows school, number, amount, split, paid to date and balance, and no phone number",
       %{conn: conn, payment: p} do
    html = conn |> get(~p"/verify/receipt/#{ReceiptVerification.token(p)}") |> html_response(200)
    assert html =~ "Reçu authentique"
    assert html =~ "R2025-000001"
    assert html =~ "Awa A" and html =~ "6e Q"
    assert html =~ "Frais exigibles"
    assert html =~ "20 000" and html =~ "40 000"
    refute html =~ "677" or html =~ "Mère A"
  end

  test "a cancelled receipt says Reçu annulé", %{conn: conn, payment: p} = ctx do
    {:ok, _} = Fees.cancel_payment(ctx.scope, p, "Erreur")
    html = conn |> get(~p"/verify/receipt/#{ReceiptVerification.token(p)}") |> html_response(200)
    assert html =~ "Reçu annulé"
  end

  test "a forged or truncated token says Reçu introuvable", %{conn: conn} do
    assert conn |> get(~p"/verify/receipt/abc") |> html_response(200) =~ "Reçu introuvable"
  end

  test "the typed number + code form finds the receipt; a wrong code does not", %{
    conn: conn,
    payment: p
  } do
    assert conn |> get(~p"/verify/receipt") |> html_response(200) =~ "Numéro du reçu"
    code = ReceiptVerification.code(ReceiptVerification.token(p))

    assert conn
           |> get(~p"/verify/receipt?#{[number: p.number, code: code]}")
           |> html_response(200) =~ "Reçu authentique"

    assert conn
           |> get(~p"/verify/receipt?#{[number: p.number, code: "000000"]}")
           |> html_response(200) =~ "Reçu introuvable"
  end
end
