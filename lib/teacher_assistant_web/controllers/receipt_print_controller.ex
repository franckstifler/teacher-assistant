defmodule TeacherAssistantWeb.ReceiptPrintController do
  @moduledoc "A payment's printable receipt (Fees 1), A5, with its QR check code. Fees axis."
  use TeacherAssistantWeb, :controller

  plug TeacherAssistantWeb.Plug.SchoolAccess

  alias TeacherAssistant.Fees
  alias TeacherAssistantWeb.ReceiptVerification

  def show(conn, %{"id" => id}) do
    with %{current_workspace: %{}} = scope <- conn.assigns.current_scope,
         true <- Fees.can_manage_fees?(scope),
         {:ok, receipt} <- Fees.receipt(scope, id) do
      token = ReceiptVerification.token(receipt.payment)
      check_url = url(~p"/verify/receipt/#{token}")

      conn
      |> put_layout(false)
      |> put_root_layout(false)
      |> render(:show,
        receipt: receipt,
        code: ReceiptVerification.code(token),
        check_url: check_url,
        lookup_url: url(~p"/verify/receipt"),
        qr: ReceiptVerification.qr_svg(check_url)
      )
    else
      _ -> redirect(conn, to: ~p"/school")
    end
  end
end
