defmodule TeacherAssistantWeb.ReceiptPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  import TeacherAssistant.FeesFixtures

  alias TeacherAssistant.{Enrollment, Fees, Organization, TeacherFixtures}
  alias TeacherAssistantWeb.ReceiptVerification

  setup :register_and_log_in_user

  setup %{scope: scope} do
    year = Organization.current_academic_year(scope)
    ctx = fees_setup(%{scope | current_academic_year: year}, year)

    {:ok, _} =
      Enrollment.add_guardian(ctx.scope, ctx.student, %{
        full_name: "Mère A",
        relationship: :mere,
        phone: "6 77 12 34 56"
      })

    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(25_500))
    Map.put(ctx, :payment, p)
  end

  test "the bursar sees the receipt with the amount in words, the QR, the code and a WhatsApp link per guardian phone",
       %{conn: conn, payment: p} do
    html = conn |> get(~p"/school/fees/receipts/#{p.id}/print") |> html_response(200)
    assert html =~ "Reçu n° R2025-000001"
    assert html =~ "vingt-cinq mille cinq cents francs CFA"
    assert html =~ "<svg"
    assert html =~ ReceiptVerification.code(ReceiptVerification.token(p))
    assert html =~ "https://wa.me/237677123456?text="
    assert html =~ "Frais exigibles"
  end

  test "a cancelled receipt is marked", %{conn: conn, payment: p} = ctx do
    {:ok, _} = Fees.cancel_payment(ctx.scope, p, "Erreur")

    assert conn |> get(~p"/school/fees/receipts/#{p.id}/print") |> html_response(200) =~
             "Reçu annulé"
  end

  test "a teacher is redirected", %{scope: scope, payment: p} do
    teacher = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)
      |> get(~p"/school/fees/receipts/#{p.id}/print")

    assert redirected_to(conn) == "/school"
  end
end
