defmodule TeacherAssistantWeb.Plug.Locale do
  @behaviour Plug
  import Plug.Conn
  @locales ~w(en fr)

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = get_session(conn, :locale) || "fr"
    locale = if locale in @locales, do: locale, else: "fr"
    Gettext.put_locale(TeacherAssistantWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end
end
