defmodule TeacherAssistantWeb.Plug.ContentSecurityPolicy do
  @moduledoc """
  The browser's security headers with a Content-Security-Policy (spec audit
  follow-ups A6): scripts only from the app itself, so an injected `<script>` or an
  inline handler never runs. Pages load `app.js` (colocated hooks are compiled into
  it) and the print pages `print.js`; neither needs an inline script.

  Each request gets a nonce in `conn.assigns.csp_nonce` for the dashboards that
  inline their own script (ErrorTracker at `/admin/errors`, the dev LiveDashboard and
  mailbox), which take it through `csp_nonce_assign_key`. Styles may be inline
  (LiveView and the print pages set them). `frame-ancestors 'self'` keeps the
  bulletin page able to show its print in a frame.

  `config :teacher_assistant, :csp_extra` adds sources per directive (dev:
  LiveDebugger's script on 127.0.0.1:4007 and the live-reload socket).
  """
  import Plug.Conn
  import Phoenix.Controller, only: [put_secure_browser_headers: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    conn
    |> assign(:csp_nonce, nonce)
    |> put_secure_browser_headers(%{"content-security-policy" => policy(nonce)})
  end

  @doc "The policy for a request whose nonce is `nonce`."
  def policy(nonce) do
    extra = Application.get_env(:teacher_assistant, :csp_extra, %{})

    [
      {"default-src", ["'self'"]},
      {"base-uri", ["'self'"]},
      {"frame-ancestors", ["'self'"]},
      {"object-src", ["'none'"]},
      {"script-src", ["'self'", "'nonce-#{nonce}'"]},
      {"style-src", ["'self'", "'unsafe-inline'"]},
      {"img-src", ["'self'", "data:", "blob:"]},
      {"font-src", ["'self'"]},
      {"connect-src", ["'self'", "wss:"]}
    ]
    |> Enum.map_join(" ", fn {directive, sources} ->
      "#{directive} #{Enum.join(sources ++ Map.get(extra, directive, []), " ")};"
    end)
  end
end
