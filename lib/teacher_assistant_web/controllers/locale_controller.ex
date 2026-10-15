defmodule TeacherAssistantWeb.LocaleController do
  use TeacherAssistantWeb, :controller
  @locales ~w(en fr)

  def set(conn, %{"locale" => locale}) do
    locale = if locale in @locales, do: locale, else: "fr"

    conn
    |> put_session(:locale, locale)
    |> redirect(to: back_path(conn))
  end

  # Back to the page the switch was clicked on. Only a same-host referer is followed, and
  # only its path and query, so the switch can never redirect off the site.
  defp back_path(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host, path: "/" <> _ = path} = uri <- URI.parse(referer),
         true <- host == conn.host,
         false <- String.starts_with?(path, "//") do
      if uri.query, do: path <> "?" <> uri.query, else: path
    else
      _ -> fallback_path(conn)
    end
  end

  # Phone accounts sign in through the session's `user_id`, not AshAuthentication's assign.
  defp fallback_path(conn) do
    if conn.assigns[:current_user] || get_session(conn, :user_id),
      do: ~p"/school",
      else: ~p"/"
  end
end
