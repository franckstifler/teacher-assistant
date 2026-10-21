defmodule TeacherAssistantWeb.FeePaperPrintControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true

  import TeacherAssistant.FeesFixtures

  alias TeacherAssistant.{FeeControl, Fees, Organization, TeacherFixtures}
  alias TeacherAssistantWeb.ReceiptVerification

  setup :register_and_log_in_user

  setup %{scope: scope} do
    year = Organization.current_academic_year(scope)
    ctx = fees_setup(%{scope | current_academic_year: year}, year)

    {:ok, _} =
      Fees.add_tranche(ctx.scope, year, %{label: "I", due_date: ~D[2025-09-01], percent: 40})

    ctx
  end

  test "note print shows reason and valid_until, no amount", %{conn: conn} = ctx do
    {:ok, note} =
      FeeControl.issue_note(ctx.scope, ctx.e, %{reason: :promise, valid_until: ~D[2025-09-30]})

    html = conn |> get(~p"/school/fees/notes/#{note.id}/print") |> html_response(200)
    assert html =~ "Autorisation de retour en classe"
    assert html =~ note.number and html =~ "Promesse de paiement" and html =~ "30/09/2025"
    assert html =~ "Awa A" and html =~ "6e Q"
    assert html =~ ReceiptVerification.code(ReceiptVerification.token(:note, note))
    assert html =~ "<svg"
    refute html =~ "FCFA"
  end

  test "warnings print renders each warning with its own code", %{conn: conn} = ctx do
    {:ok, %{enrollment: e2}} =
      TeacherAssistant.Enrollment.enroll_new(ctx.scope, ctx.cg, %{full_name: "Ben B", sex: :m})

    {:ok, [w1, w2]} = FeeControl.issue_warnings(ctx.scope, [ctx.e, e2], ~D[2025-09-22])

    html =
      conn
      |> get(~p"/school/fees/warnings/print?#{[ids: "#{w1.id},#{w2.id}"]}")
      |> html_response(200)

    assert html =~ "Avis de retard de paiement"
    assert html =~ w1.number and html =~ w2.number
    assert html =~ ReceiptVerification.code(ReceiptVerification.token(:warning, w1))
    assert html =~ ReceiptVerification.code(ReceiptVerification.token(:warning, w2))
    assert html =~ "Merci de régler cette somme avant le 22/09/2025."

    assert html =~ "Passé ce délai, l&#39;élève pourra être renvoyé jusqu&#39;au paiement." or
             html =~ "Passé ce délai, l'élève pourra être renvoyé jusqu'au paiement."
  end

  test "a teacher is sent away from the print routes", ctx do
    {:ok, note} =
      FeeControl.issue_note(ctx.scope, ctx.e, %{reason: :promise, valid_until: ~D[2025-09-30]})

    teacher = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:teacher]})

    conn =
      build_conn()
      |> log_in_user(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, ctx.scope.current_workspace.id)

    assert redirected_to(get(conn, ~p"/school/fees/notes/#{note.id}/print")) =~ "/school"
    assert redirected_to(get(conn, ~p"/school/fees/warnings/print?ids=x")) =~ "/school"
  end
end
