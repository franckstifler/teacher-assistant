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
    assert html =~ "Ce paiement ne compte pas."
  end

  test "a forged or truncated token says Document introuvable", %{conn: conn} do
    assert conn |> get(~p"/verify/receipt/abc") |> html_response(200) =~ "Document introuvable"
  end

  test "the typed number + code form finds the receipt; a wrong code does not", %{
    conn: conn,
    payment: p
  } do
    html = conn |> get(~p"/verify/receipt") |> html_response(200)
    assert html =~ "Numéro du document"
    assert html =~ ~s(autocapitalize="characters")
    code = ReceiptVerification.code(ReceiptVerification.token(p))

    assert conn
           |> get(~p"/verify/receipt?#{[number: p.number, code: code]}")
           |> html_response(200) =~ "Reçu authentique"

    assert conn
           |> get(~p"/verify/receipt?#{[number: p.number, code: "000000"]}")
           |> html_response(200) =~ "Document introuvable"
  end

  describe "Fees 2 papers" do
    setup ctx do
      {:ok, _} =
        Fees.add_tranche(ctx.scope, ctx.year, %{label: "I", due_date: ~D[2025-09-01], percent: 40})

      :ok
    end

    test "a note shows valid today, its reason and date, no amount, no phone",
         %{conn: conn} = ctx do
      {:ok, note} =
        TeacherAssistant.FeeControl.issue_note(ctx.scope, ctx.e, %{
          reason: :promise,
          valid_until: ~D[2025-09-30]
        })

      html =
        conn
        |> get(~p"/verify/note/#{ReceiptVerification.token(:note, note)}")
        |> html_response(200)

      assert html =~ "Autorisation valable aujourd&#39;hui" or
               html =~ "Autorisation valable aujourd'hui"

      assert html =~ "A2025-000001" and html =~ "Promesse de paiement" and html =~ "30/09/2025"
      refute html =~ "FCFA"
      refute html =~ "677"
    end

    test "an expired note says expirée", %{conn: conn} = ctx do
      note =
        TeacherAssistant.Academics.ReturnNote
        |> Ash.Changeset.for_create(
          :create,
          %{
            enrollment_id: ctx.e.id,
            academic_year_id: ctx.year.id,
            seq: 1,
            number: "A2025-000001",
            reason: :promise,
            issued_on: ~D[2025-09-01],
            valid_until: ~D[2025-09-10],
            student_name: "Awa A",
            class_label: "6e Q"
          },
          scope: ctx.scope
        )
        |> Ash.create!()

      html =
        conn
        |> get(~p"/verify/note/#{ReceiptVerification.token(:note, note)}")
        |> html_response(200)

      assert html =~ "Autorisation expirée depuis le 10/09/2025"
    end

    test "a warning shows its lines and total, no phone", %{conn: conn} = ctx do
      {:ok, [w]} =
        TeacherAssistant.FeeControl.issue_warnings(ctx.scope, [ctx.e], ~D[2025-09-22])

      html =
        conn
        |> get(~p"/verify/warning/#{ReceiptVerification.token(:warning, w)}")
        |> html_response(200)

      assert html =~ "Avis authentique"
      assert html =~ "Frais exigibles" and html =~ "4 000 FCFA" and html =~ "22/09/2025"
      refute html =~ "677"
    end

    test "the typed form says it checks receipts, notes and warnings", %{conn: conn} do
      html = conn |> get(~p"/verify/receipt") |> html_response(200)
      assert html =~ "Vérifier un reçu, une autorisation ou un avis"
      assert html =~ "R2026-000123 / A2026-000045 / V2026-000067"
    end

    test "old receipt links still work", %{conn: conn, payment: p} do
      assert conn
             |> get(~p"/verify/receipt/#{ReceiptVerification.token(p)}")
             |> html_response(200) =~ "Reçu authentique"
    end
  end
end
