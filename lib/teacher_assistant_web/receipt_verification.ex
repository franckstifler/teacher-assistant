defmodule TeacherAssistantWeb.ReceiptVerification do
  @moduledoc """
  The QR code and code on a printed receipt (Fees 1), modelled on the report-card one
  (spec I5): the token is the two 16-byte ids `{workspace, payment}` followed by a 16-byte
  HMAC-SHA256 tag keyed from `secret_key_base`, base64url-encoded (64 characters).
  Someone without a camera types the receipt number and a 6-character code drawn from
  the token: Crockford base32 (no I, L, O, U), read back ignoring case, spaces and the
  O/0, I/L/1 mix-ups a phone keyboard or a reader makes.
  Rotating `secret_key_base` invalidates printed codes.
  """
  import Bitwise

  alias TeacherAssistant.Fees

  @salt "receipt-verify"
  @tag_bytes 16

  def token(%{workspace_id: ws, id: id}) do
    ids = dump(ws) <> dump(id)
    Base.url_encode64(ids <> tag(ids), padding: false)
  end

  @alphabet ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"

  @doc "The 6 characters printed under the QR code."
  def code(token) do
    <<bits::30, _::bitstring>> = :crypto.hash(:sha256, token)

    for shift <- [25, 20, 15, 10, 5, 0],
        into: "",
        do: <<Enum.at(@alphabet, bits >>> shift &&& 31)>>
  end

  # What the reader typed, read the way it was meant.
  defp normalize_code(code) do
    code
    |> String.upcase()
    |> String.replace(~r/[\s-]/u, "")
    |> String.replace("O", "0")
    |> String.replace(["I", "L"], "1")
  end

  def verify(token) when is_binary(token) do
    with {:ok, <<ids::binary-size(32), tag::binary-size(@tag_bytes)>>} <-
           Base.url_decode64(token, padding: false),
         true <- Plug.Crypto.secure_compare(tag, tag(ids)),
         <<ws::binary-size(16), payment::binary-size(16)>> = ids,
         {:ok, ws} <- Ecto.UUID.load(ws),
         {:ok, payment} <- Ecto.UUID.load(payment) do
      Fees.verification(ws, payment)
    else
      _ -> :invalid
    end
  end

  def verify(_token), do: :invalid

  @doc "The typed check: a receipt with this number whose code matches, else `:invalid`."
  def lookup(number, code) when is_binary(number) and is_binary(code) do
    code = normalize_code(code)

    number
    |> Fees.find_by_number()
    |> Enum.find_value(:invalid, fn {ws, id} ->
      token = token(%{workspace_id: ws, id: id})
      if Plug.Crypto.secure_compare(code(token), code), do: verify(token)
    end)
  end

  def lookup(_number, _code), do: :invalid

  def qr_svg(url), do: url |> EQRCode.encode() |> EQRCode.svg(width: 88)

  defp tag(ids) do
    key =
      Plug.Crypto.KeyGenerator.generate(
        TeacherAssistantWeb.Endpoint.config(:secret_key_base),
        @salt
      )

    binary_part(:crypto.mac(:hmac, :sha256, key, ids), 0, @tag_bytes)
  end

  defp dump(uuid), do: Ecto.UUID.dump!(uuid)
end
