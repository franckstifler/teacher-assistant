defmodule TeacherAssistantWeb.BulletinVerifyController do
  @moduledoc "Public check of a printed report card's QR code (spec I5): no login, no marks."
  use TeacherAssistantWeb, :controller

  alias TeacherAssistantWeb.BulletinVerification

  def show(conn, %{"token" => token}) do
    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:show, result: BulletinVerification.verify(token))
  end
end
