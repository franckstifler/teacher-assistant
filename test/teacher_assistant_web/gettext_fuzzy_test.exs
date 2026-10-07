defmodule TeacherAssistantWeb.GettextFuzzyTest do
  @moduledoc """
  Gettext renders a fuzzy message's msgstr, and `mix gettext.extract --merge` fills new
  messages with guesses borrowed from look-alikes (« Ville » → « Fille »). A fuzzy
  message must therefore carry no text: translate it and drop the flag, or leave it empty.
  """
  use ExUnit.Case, async: true

  for locale <- ~w(fr en) do
    test "no fuzzy message carries a translation (#{locale})" do
      path = "priv/gettext/#{unquote(locale)}/LC_MESSAGES/default.po"

      offenders =
        for message <- Expo.PO.parse_file!(path).messages,
            Expo.Message.has_flag?(message, "fuzzy"),
            translated?(message),
            do: Expo.Message.key(message)

      assert offenders == []
    end
  end

  defp translated?(%Expo.Message.Singular{msgstr: msgstr}), do: IO.iodata_to_binary(msgstr) != ""

  defp translated?(%Expo.Message.Plural{msgstr: msgstr}),
    do: Enum.any?(msgstr, fn {_n, text} -> IO.iodata_to_binary(text) != "" end)
end
