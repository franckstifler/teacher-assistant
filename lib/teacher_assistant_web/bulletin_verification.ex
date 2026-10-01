defmodule TeacherAssistantWeb.BulletinVerification do
  @moduledoc """
  The QR code on a published report card (spec I5): a signed token over
  `{workspace_id, publication_id, student_id}`, with no expiry, so every reprint
  carries the same code. Rotating `secret_key_base` invalidates printed codes.
  """
  alias TeacherAssistant.ReportCards

  @salt "bulletin-verify"

  def token(pub, student_id),
    do: Phoenix.Token.sign(TeacherAssistantWeb.Endpoint, @salt, {pub.workspace_id, pub.id, student_id})

  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(TeacherAssistantWeb.Endpoint, @salt, token, max_age: :infinity) do
      {:ok, {workspace_id, publication_id, student_id}} ->
        ReportCards.verification(workspace_id, publication_id, student_id)

      _ ->
        :invalid
    end
  end

  def qr_svg(url), do: url |> EQRCode.encode() |> EQRCode.svg(width: 88)
end
