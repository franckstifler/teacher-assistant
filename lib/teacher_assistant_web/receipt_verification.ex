defmodule TeacherAssistantWeb.ReceiptVerification do
  @moduledoc """
  The QR code and code on a printed receipt (Fees 1), modelled on the report-card one
  (spec I5): the token is the two 16-byte ids `{workspace, payment}` followed by a 16-byte
  HMAC-SHA256 tag keyed from `secret_key_base`, base64url-encoded (64 characters).
  Someone without a camera types the receipt number and a 6-character code drawn from
  the token: Crockford base32 (no I, L, O, U), read back ignoring case, spaces and the
  O/0, I/L/1 mix-ups a phone keyboard or a reader makes.
  Rotating `secret_key_base` invalidates printed codes.

  Fees 2 adds two more papers checked the same way: return notes (`A…` numbers) and
  warnings (`V…`). Each kind has its own salt, so one kind's token or code never opens
  another kind's paper.
  """
  import Bitwise

  alias TeacherAssistant.{FeeControl, Fees, RateLimit}

  @salts %{receipt: "receipt-verify", note: "note-verify", warning: "warning-verify"}
  @tag_bytes 16
  @max_failed_lookups 20
  @lookup_window :timer.hours(1)

  @doc "A receipt's token (Fees 1)."
  def token(record), do: token(:receipt, record)

  @doc "The token of a `:receipt`, `:note` or `:warning`."
  def token(kind, %{workspace_id: ws, id: id}) do
    ids = dump(ws) <> dump(id)
    Base.url_encode64(ids <> tag(kind, ids), padding: false)
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

  @doc "A receipt's check (Fees 1)."
  def verify(token), do: verify(:receipt, token)

  @doc "What the school recorded for the paper of `kind` behind `token`, or `:invalid`."
  def verify(kind, token) when is_binary(token) and is_map_key(@salts, kind) do
    with {:ok, <<ids::binary-size(32), tag::binary-size(@tag_bytes)>>} <-
           Base.url_decode64(token, padding: false),
         true <- Plug.Crypto.secure_compare(tag, tag(kind, ids)),
         <<ws::binary-size(16), id::binary-size(16)>> = ids,
         {:ok, ws} <- Ecto.UUID.load(ws),
         {:ok, id} <- Ecto.UUID.load(id) do
      record(kind, ws, id)
    else
      _ -> :invalid
    end
  end

  def verify(_kind, _token), do: :invalid

  defp record(:receipt, ws, id), do: Fees.verification(ws, id)
  defp record(:note, ws, id), do: FeeControl.note_verification(ws, id)
  defp record(:warning, ws, id), do: FeeControl.warning_verification(ws, id)

  @doc """
  The typed check: a paper with this number whose code matches, else `:invalid`. The
  number's letter tells the kind: `A` notes, `V` warnings, anything else receipts.
  After #{@max_failed_lookups} wrong codes for one number within an hour, `:throttled`
  until the hour ends: numbers are sequential and shared by every school, so the
  code is all that stands between a guesser and a student's name and payments.
  """
  def lookup(number, code) when is_binary(number) and is_binary(code) do
    key = "receipt_lookup:" <> (number |> String.trim() |> String.upcase())

    if RateLimit.get(key, @lookup_window) >= @max_failed_lookups do
      :throttled
    else
      with :invalid <- match_code(number, normalize_code(code)) do
        RateLimit.inc(key, @lookup_window)
        :invalid
      end
    end
  end

  def lookup(_number, _code), do: :invalid

  defp match_code(number, code) do
    kind = kind_of(number)

    number
    |> find_by_number(kind)
    |> Enum.find_value(:invalid, fn {ws, id} ->
      token = token(kind, %{workspace_id: ws, id: id})
      if Plug.Crypto.secure_compare(code(token), code), do: verify(kind, token)
    end)
  end

  defp kind_of(number) do
    case number |> String.trim() |> String.upcase() do
      "A" <> _ -> :note
      "V" <> _ -> :warning
      _ -> :receipt
    end
  end

  defp find_by_number(number, :receipt), do: Fees.find_by_number(number)
  defp find_by_number(number, :note), do: FeeControl.find_note_by_number(number)
  defp find_by_number(number, :warning), do: FeeControl.find_warning_by_number(number)

  def qr_svg(url), do: url |> EQRCode.encode() |> EQRCode.svg(width: 88)

  defp tag(kind, ids) do
    key =
      Plug.Crypto.KeyGenerator.generate(
        TeacherAssistantWeb.Endpoint.config(:secret_key_base),
        Map.fetch!(@salts, kind)
      )

    binary_part(:crypto.mac(:hmac, :sha256, key, ids), 0, @tag_bytes)
  end

  defp dump(uuid), do: Ecto.UUID.dump!(uuid)
end
