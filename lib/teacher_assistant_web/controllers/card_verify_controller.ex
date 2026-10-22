defmodule TeacherAssistantWeb.CardVerifyController do
  @moduledoc "Public check of a school ID card's QR code (spec bulletin v2 §7): no login."
  use TeacherAssistantWeb, :controller

  alias TeacherAssistantWeb.CardVerification

  def show(conn, %{"token" => token}) do
    conn
    |> put_layout(false)
    |> put_root_layout(false)
    |> render(:show, result: CardVerification.verify(token))
  end
end
