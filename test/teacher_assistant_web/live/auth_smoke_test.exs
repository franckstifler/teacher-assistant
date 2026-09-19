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

    assert html =~ "Content de vous revoir"
    assert html =~ "Se connecter"
    assert html =~ "Mot de passe oublié ?"
    assert html =~ "Rester connecté"
    assert html =~ "Tout l&#39;établissement sur un seul tableau."
    # magic-link UI (and the sign-in/register/reset forms not matching the
    # current live_action) are hidden via CSS, not removed from the DOM
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

  test "token-based password reset page renders", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/password-reset/some-token")

    assert html =~ "Choisissez un nouveau mot de passe"
    assert html =~ "Mot de passe"
  end
end
