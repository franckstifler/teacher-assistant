defmodule TeacherAssistantWeb.RememberMeTest do
  @moduledoc """
  « Rester connecté »: a ticked box on either sign-in form leaves a 30-day cookie
  that signs the person back in once the browser has dropped its session (phones
  close the browser in the background). Signing out, a password reset or an
  expired temporary password ends it.
  """
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Accounts, TeacherFixtures}

  @cookie "remember_me"

  setup do
    %{scope: scope} = TeacherFixtures.setup_complete_school_fixture()

    {:ok, %{user: user, temporary_password: pw}} =
      Accounts.add_member_by_phone(scope, %{name: "Awa", phone: "677123456", roles: [:teacher]})

    %{user: user, password: pw}
  end

  # Signs in through the phone form, with the box ticked or not; returns the conn
  # of the auth controller's response.
  defp sign_in(conn, password, remember_me) do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    {:error, {:redirect, %{to: to}}} =
      view
      |> form("#phone-sign-in form", %{
        "user" => %{
          "phone" => "677123456",
          "password" => password,
          "remember_me" => to_string(remember_me)
        }
      })
      |> render_submit()

    get(conn, to)
  end

  # A browser that kept only the cookie: no session left.
  defp returning_browser(cookie_value) do
    build_conn() |> put_req_cookie(@cookie, cookie_value)
  end

  defp signed_in?(conn), do: is_binary(get_session(conn, "user_token"))

  test "both sign-in forms offer « Rester connecté », ticked", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    for form <- ["#phone-sign-in", "#email-sign-in"] do
      assert has_element?(view, "#{form} input[type=checkbox][name='user[remember_me]'][checked]")
      assert view |> element(form) |> render() =~ "Rester connecté"
    end
  end

  test "a ticked box leaves a 30-day cookie that signs the person back in", %{
    conn: conn,
    password: pw
  } do
    conn = sign_in(conn, pw, true)
    assert signed_in?(conn)

    assert %{value: token, max_age: max_age, http_only: true} = conn.resp_cookies[@cookie]
    assert max_age >= 29 * 24 * 3600

    # the browser closed: only the cookie is left
    back = get(returning_browser(token), ~p"/school")
    assert signed_in?(back)
    refute redirected_to(back) =~ "/sign-in"
  end

  test "an unticked box leaves no cookie", %{conn: conn, password: pw} do
    conn = sign_in(conn, pw, false)
    assert signed_in?(conn)
    refute Map.has_key?(conn.resp_cookies, @cookie)
  end

  test "signing out deletes the cookie and ends it", %{conn: conn, password: pw} do
    conn = sign_in(conn, pw, true)
    %{value: token} = conn.resp_cookies[@cookie]

    out =
      build_conn()
      |> put_req_cookie(@cookie, token)
      |> get(~p"/school")
      |> recycle()
      |> delete(~p"/sign-out")

    assert %{max_age: 0} = out.resp_cookies[@cookie]

    back = get(returning_browser(token), ~p"/school")
    refute signed_in?(back)
    assert redirected_to(back) =~ "/sign-in"
  end

  test "a password reset by the school ends it", %{conn: conn, password: pw, user: user} do
    %{value: token} = sign_in(conn, pw, true).resp_cookies[@cookie]

    :ok = Accounts.revoke_all_sessions(user)

    back = get(returning_browser(token), ~p"/school")
    refute signed_in?(back)
    assert redirected_to(back) =~ "/sign-in"
  end

  test "an expired temporary password gets no cookie", %{conn: conn, password: pw, user: user} do
    TeacherAssistant.Repo.query!(
      "update users set temporary_password_expires_at = now() - interval '1 day' where id = $1",
      [Ecto.UUID.dump!(user.id)]
    )

    conn = sign_in(conn, pw, true)

    refute signed_in?(conn)
    assert redirected_to(conn) == ~p"/sign-in"
    assert %{max_age: 0} = conn.resp_cookies[@cookie]
  end
end
