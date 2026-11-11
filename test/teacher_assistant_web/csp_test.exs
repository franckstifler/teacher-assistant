defmodule TeacherAssistantWeb.CspTest do
  @moduledoc "Every page under a Content-Security-Policy, no inline script (spec audit follow-ups A6)."
  use TeacherAssistantWeb.ConnCase, async: true

  alias TeacherAssistant.TeacherFixtures

  defp csp(conn) do
    [policy] = get_resp_header(conn, "content-security-policy")
    policy
  end

  describe "the policy" do
    setup :register_and_log_in_user

    test "/school carries it: own scripts plus a nonce, never unsafe-inline scripts", %{
      conn: conn
    } do
      policy = conn |> get(~p"/school") |> csp()
      assert policy =~ "default-src 'self'"
      assert policy =~ ~r/script-src 'self' 'nonce-[A-Za-z0-9_-]+'/
      refute policy =~ ~r/script-src[^;]*'unsafe-inline'/
      assert policy =~ "img-src 'self' data: blob:"
      assert policy =~ "style-src 'self' 'unsafe-inline'"
      assert policy =~ "frame-ancestors 'self'"
      assert policy =~ "base-uri 'self'"
      assert policy =~ "object-src 'none'"
    end

    test "each request gets its own nonce", %{conn: conn} do
      [a, b] = for _ <- 1..2, do: conn |> get(~p"/school") |> csp()
      refute a == b
    end
  end

  test "the landing and sign-in pages carry it too", %{conn: conn} do
    assert conn |> get(~p"/") |> csp() =~ "script-src 'self'"
    assert build_conn() |> get(~p"/sign-in") |> csp() =~ "script-src 'self'"
  end

  test "the error dashboard renders for an operator with the nonce on its inline script" do
    op = TeacherFixtures.admin_user_fixture()
    conn = build_conn() |> log_in_user(op) |> get(~p"/admin/errors")
    html = html_response(conn, 200)
    [_, nonce] = Regex.run(~r/'nonce-([A-Za-z0-9_-]+)'/, csp(conn))
    assert html =~ ~s(nonce="#{nonce}")
  end

  test "no template or component carries an inline event handler" do
    offenders =
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          File.read!(path) =~ ~r/\son(click|change|submit|load|input)="/,
          do: path

    assert offenders == []
  end

  test "every print page loads print.js through the shared setup" do
    html =
      Phoenix.LiveViewTest.rendered_to_string(
        TeacherAssistantWeb.PrintComponents.setup(%{paper: :a4, __changed__: nil})
      )

    assert html =~ ~r{<script[^>]+src="/assets/js/print[^"]*\.js"}
  end
end
