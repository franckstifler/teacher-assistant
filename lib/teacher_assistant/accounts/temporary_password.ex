defmodule TeacherAssistant.Accounts.TemporaryPassword do
  @moduledoc """
  One-time passwords a school hands to a teacher by voice, WhatsApp or SMS:
  two pronounceable 4-letter words and 4 digits, e.g. `kola-mabu-4827`
  (~38 bits). Letters that are easily confused when dictated (c, q, x, j, h,
  w, y) are left out. Uses `:crypto`, never `:rand`.
  """

  @consonants ~c"bdfgklmnprstvz"
  @vowels ~c"aeiou"

  def generate do
    "#{word()}-#{word()}-#{digits()}"
  end

  defp word do
    for pick <- [@consonants, @vowels, @consonants, @vowels], into: "", do: <<pick_one(pick)>>
  end

  defp digits do
    random(10_000) |> Integer.to_string() |> String.pad_leading(4, "0")
  end

  defp pick_one(chars), do: Enum.at(chars, random(length(chars)))

  defp random(n), do: :crypto.strong_rand_bytes(4) |> :binary.decode_unsigned() |> rem(n)
end
