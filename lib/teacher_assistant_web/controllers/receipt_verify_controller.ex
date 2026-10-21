defmodule TeacherAssistantWeb.ReceiptVerifyController do
  @moduledoc """
  Public check of a printed fee paper — receipt (Fees 1), return note or warning (Fees 2):
  by QR token, or by number + code. No login.
  """
  use TeacherAssistantWeb, :controller

  alias TeacherAssistantWeb.ReceiptVerification

  def show(conn, %{"token" => token}),
    do: render_page(conn, ReceiptVerification.verify(token), false)

  def show_note(conn, %{"token" => token}),
    do: render_page(conn, ReceiptVerification.verify(:note, token), false)

  def show_warning(conn, %{"token" => token}),
    do: render_page(conn, ReceiptVerification.verify(:warning, token), false)

  def lookup(conn, %{"number" => number, "code" => code})
      when is_binary(number) and is_binary(code),
      do: render_page(conn, ReceiptVerification.lookup(number, code), true)

  def lookup(conn, _params), do: render_page(conn, nil, true)

  defp render_page(conn, result, form?) do
    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:show, result: result, form?: form?)
  end
end
