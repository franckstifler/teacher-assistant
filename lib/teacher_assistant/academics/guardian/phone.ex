defmodule TeacherAssistant.Academics.Guardian.Phone do
  @moduledoc "Spec KLM1: the comparable form of a phone number (duplicate lookup)."

  @doc "Digits only; a leading 237 or 00237 is dropped when 9 digits remain."
  def key(nil), do: nil

  def key(phone) when is_binary(phone) do
    case String.replace(phone, ~r/\D/, "") do
      "00237" <> rest when byte_size(rest) == 9 -> rest
      "237" <> rest when byte_size(rest) == 9 -> rest
      digits -> digits
    end
  end

  @doc "Whether `phone` is long enough to be a real number."
  def valid?(phone), do: String.length(key(phone) || "") >= 8
end
