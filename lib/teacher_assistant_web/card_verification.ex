defmodule TeacherAssistantWeb.CardVerification do
  @moduledoc """
  Spec bulletin v2 §7: the QR code on a school ID card. Built like
  `BulletinVerification`: the two 16-byte ids `{workspace, enrollment}` followed by a
  16-byte HMAC-SHA256 tag keyed from `secret_key_base` with its own salt, base64url.
  """
  alias TeacherAssistant.Enrollment

  @salt "card-verify"
  @tag_bytes 16

  def token(workspace_id, enrollment_id) do
    ids = dump(workspace_id) <> dump(enrollment_id)
    Base.url_encode64(ids <> tag(ids), padding: false)
  end

  def verify(token) when is_binary(token) do
    with {:ok, <<ids::binary-size(32), tag::binary-size(@tag_bytes)>>} <-
           Base.url_decode64(token, padding: false),
         true <- Plug.Crypto.secure_compare(tag, tag(ids)),
         <<ws::binary-size(16), enrollment::binary-size(16)>> = ids,
         {:ok, ws} <- Ecto.UUID.load(ws),
         {:ok, enrollment} <- Ecto.UUID.load(enrollment) do
      Enrollment.card_verification(ws, enrollment)
    else
      _ -> :invalid
    end
  end

  def qr_svg(url), do: url |> EQRCode.encode() |> EQRCode.svg(width: 46)

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
