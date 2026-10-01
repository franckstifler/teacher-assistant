defmodule TeacherAssistantWeb.BulletinVerification do
  @moduledoc """
  The QR code on a published report card (spec I5). The token is the three 16-byte
  ids `{workspace, publication, student}` followed by a 16-byte HMAC-SHA256 tag keyed
  from `secret_key_base`, base64url-encoded (86 characters): short enough for a small
  printed QR, impossible to forge, and the same at every reprint. Rotating
  `secret_key_base` invalidates printed codes.
  """
  alias TeacherAssistant.ReportCards

  @salt "bulletin-verify"
  @tag_bytes 16

  def token(pub, student_id) do
    ids = dump(pub.workspace_id) <> dump(pub.id) <> dump(student_id)
    Base.url_encode64(ids <> tag(ids), padding: false)
  end

  def verify(token) when is_binary(token) do
    with {:ok, <<ids::binary-size(48), tag::binary-size(@tag_bytes)>>} <-
           Base.url_decode64(token, padding: false),
         true <- Plug.Crypto.secure_compare(tag, tag(ids)),
         <<ws::binary-size(16), pub::binary-size(16), student::binary-size(16)>> = ids,
         {:ok, ws} <- Ecto.UUID.load(ws),
         {:ok, pub} <- Ecto.UUID.load(pub),
         {:ok, student} <- Ecto.UUID.load(student) do
      ReportCards.verification(ws, pub, student)
    else
      _ -> :invalid
    end
  end

  def qr_svg(url), do: url |> EQRCode.encode() |> EQRCode.svg(width: 88)

  defp tag(ids) do
    key =
      Plug.Crypto.KeyGenerator.generate(
        TeacherAssistantWeb.Endpoint.config(:secret_key_base),
        @salt
      )

    :crypto.mac(:hmac, :sha256, key, ids) |> binary_part(0, @tag_bytes)
  end

  defp dump(uuid) do
    {:ok, binary} = Ecto.UUID.dump(uuid)
    binary
  end
end
