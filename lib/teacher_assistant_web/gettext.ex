defmodule TeacherAssistantWeb.Gettext do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://hexdocs.pm/gettext), your module compiles translations
  that you can use in your application. To use this Gettext backend module,
  call `use Gettext` and pass it as an option:

      use Gettext, backend: TeacherAssistantWeb.Gettext

      # Simple translation
      gettext("Here is the string to translate")

      # Plural translation
      ngettext("Here is the string to translate",
               "Here are the strings to translate",
               3)

      # Domain-based translation
      dgettext("errors", "Here is the error message to translate")

  See the [Gettext Docs](https://hexdocs.pm/gettext) for detailed usage.
  """
  use Gettext.Backend, otp_app: :teacher_assistant

  # French source strings: an empty msgstr falls back to the msgid. Gettext's default fallback
  # picks the singular only for `n == 1` (the English rule), so « 0 demandes ». Pick the
  # singular by the locale's own plural rule instead (French: 0 and 1 are singular).
  @impl Gettext.Backend
  def handle_missing_plural_translation(
        locale,
        domain,
        _msgctxt,
        msgid,
        msgid_plural,
        n,
        bindings
      ) do
    Gettext.Compiler.warn_if_domain_contains_slashes(domain)
    string = if singular?(locale, n), do: msgid, else: msgid_plural

    with {:ok, interpolated} <-
           Gettext.Interpolation.Default.runtime_interpolate(string, Map.put(bindings, :count, n)),
         do: {:default, interpolated}
  end

  defp singular?(locale, n) do
    Gettext.Plural.plural(locale, n) == 0
  rescue
    _ -> n == 1
  end
end
