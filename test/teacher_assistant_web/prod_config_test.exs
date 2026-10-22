defmodule TeacherAssistantWeb.ProdConfigTest do
  @moduledoc "The production transport settings, read from config/prod.exs (not loaded in test)."
  use ExUnit.Case, async: true
  import Plug.Test

  @prod Config.Reader.read!("config/prod.exs", env: :prod)

  defp force_ssl,
    do: get_in(@prod, [:teacher_assistant, TeacherAssistantWeb.Endpoint, :force_ssl])

  test "the session cookie is marked Secure in production" do
    assert get_in(@prod, [:teacher_assistant, :secure_session_cookie]) == true
  end

  test "plain HTTP is redirected to HTTPS, with HSTS" do
    opts = Plug.SSL.init(force_ssl())

    conn = :get |> conn("http://app.example.cm/school") |> Plug.SSL.call(opts)
    assert conn.status == 301
    assert Plug.Conn.get_resp_header(conn, "location") == ["https://app.example.cm/school"]

    conn = :get |> conn("https://app.example.cm/school") |> Plug.SSL.call(opts)
    refute conn.halted
    assert [_] = Plug.Conn.get_resp_header(conn, "strict-transport-security")
  end

  test "a request the TLS proxy forwarded as HTTPS is not redirected" do
    opts = Plug.SSL.init(force_ssl())

    conn =
      :get
      |> conn("http://app.example.cm/school")
      |> Plug.Conn.put_req_header("x-forwarded-proto", "https")
      |> Plug.SSL.call(opts)

    refute conn.halted
  end
end
