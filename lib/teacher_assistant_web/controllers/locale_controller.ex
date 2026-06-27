defmodule TeacherAssistantWeb.LocaleController do
  use TeacherAssistantWeb, :controller
  @locales ~w(en fr)

  def set(conn, %{"locale" => locale}) do
    locale = if locale in @locales, do: locale, else: "fr"

    conn
    |> put_session(:locale, locale)
    |> redirect(to: ~p"/teacher")
  end
end
