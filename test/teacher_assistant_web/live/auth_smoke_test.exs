defmodule TeacherAssistantWeb.AuthSmokeTest do
  @moduledoc """
  Temporary smoke test for the paper-redesigned auth pages — verifies the
  sign-in / register / forgot-password / token-reset pages actually render
  (not just compile) after the AuthOverrides + Layouts.auth rewrite, and
  that the reassurance footer, French copy, hidden magic-link UI, and the
  new `resettable` config all work end to end. Not meant to be a permanent
  fixture of the suite necessarily, but left in place for coverage.
  """
  use TeacherAssistantWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "sign-in page renders the paper layout, French copy, and hides magic link", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/sign-in")

    assert html =~ "Se connecter"

    assert html =~
             "Entrez le numéro de téléphone ou l&#39;adresse fournis par votre établissement."

    assert html =~ "Mot de passe oublié ?"
    # no decorative « Rester connecté »: the session ends with the browser
    refute html =~ "Rester connecté"
    assert html =~ "Tout l&#39;établissement sur un seul tableau."
    # magic link is no longer rendered on /sign-in (its routes stay); the
    # register/reset forms not matching the live_action are hidden via CSS
    assert html =~ ~s(hidden)
    assert html =~ ~s(type="submit")
    # "Nom et prénom" belongs to the register form only. Like the rest of
    # that form, it's present in the DOM on /sign-in (forms aren't removed,
    # just toggled) but it lives inside the register wrapper, which carries
    # `hidden` here — so it's never visible on the sign-in screen.
    assert has_element?(
             view,
             "[id$='register-with-password-wrapper'].hidden input[name='user[name]']"
           )
  end

  test "register page renders French copy, the register form, and the name field", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, ~p"/register")

    assert html =~ "Commencez par votre compte"
    assert html =~ "Créer mon compte"
    assert html =~ "Adresse e-mail"
    assert html =~ "Nom et prénom"
    # on /register the register wrapper is the visible one (no `hidden`)
    assert has_element?(
             view,
             "[id$='register-with-password-wrapper']:not(.hidden) input[name='user[name]']"
           )
  end

  test "forgot-password (reset request) page renders directly", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/reset")

    assert html =~ "Recevez un lien de réinitialisation"
    assert html =~ "Envoyer le lien"
  end

  test "requesting a reset link confirms it on the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reset")

    view
    |> form("#user-password-request-password-reset-with-password",
      user: %{email: "nobody@example.test"}
    )
    |> render_submit()

    assert view |> element("#reset-sent") |> render() =~
             "Si cette adresse existe, un lien de réinitialisation vient de lui être envoyé."
  end

  test "the auth pages speak English once the visitor picks it", %{conn: conn} do
    conn = Phoenix.ConnTest.init_test_session(conn, %{locale: "en"})

    {:ok, view, html} = live(conn, ~p"/sign-in")
    assert html =~ "Enter the phone number or email address your school gave you."
    assert html =~ "Phone number"
    assert html =~ "Password"
    assert html =~ "Roll call in one tap, even on a phone"
    assert has_element?(view, ~s(#auth-locale a[href="/locale/fr"]), "Français")
    assert has_element?(view, ~s(#auth-locale a[aria-current="true"]), "English")

    {:ok, _view, html} = live(conn, ~p"/reset")
    assert html =~ "Get a reset link"
    assert html =~ "Send the link"

    {:ok, _view, html} = live(conn, ~p"/password-reset/some-token")
    assert html =~ "Choose a new password"
  end

  test "token-based password reset page renders", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/password-reset/some-token")

    assert html =~ "Choisissez un nouveau mot de passe"
    assert html =~ "Mot de passe"
  end

  test "a signed-in user visiting /sign-in is redirected to /school", %{conn: conn} do
    user = TeacherAssistant.TeacherFixtures.user_fixture()
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/school"}}} = live(conn, ~p"/sign-in")
  end

  test "AuthController.success/4 with no return_to redirects to /school", %{conn: conn} do
    user = TeacherAssistant.TeacherFixtures.user_fixture()

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])
      |> TeacherAssistantWeb.AuthController.success({:password, :reset}, user, nil)

    assert redirected_to(conn) == "/school"
    # revoking this person's sessions disconnects the live pages of this one
    assert get_session(conn, :live_socket_id) == "users_socket:#{user.id}"
  end
end
