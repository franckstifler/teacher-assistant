defmodule TeacherAssistantWeb.PageControllerTest do
  use TeacherAssistantWeb.ConnCase

  test "GET / renders the landing page with both audience lanes", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Teacher Assistant"
    # hero headline (pixel-matched French landing design)
    assert html =~ "Tout l'établissement sur un seul tableau"
    # the two ways in — school vs teacher — live in the #portes section
    assert html =~ ~s(id="portes")
    assert html =~ "Deux façons de commencer"
    # each role has its screen, and there's a pricing section
    assert html =~ ~s(id="roles")
    assert html =~ ~s(id="prix")
  end

  test "GET / links to every entry point the front door needs", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    # account + session
    assert html =~ ~s(href="/register")
    assert html =~ ~s(href="/sign-in")
    # school onboarding intent (carries you to school setup after auth)
    assert html =~ ~s(href="/schools/start")
    # bilingual switch
    assert html =~ ~s(href="/locale/fr")
    assert html =~ ~s(href="/locale/en")
  end

  test "GET /schools/start sends a visitor to register, bound for school setup", %{conn: conn} do
    conn = get(conn, ~p"/schools/start")

    # differentiation happens after auth: the school intent lands on /schools/new,
    # not the default /teacher dashboard
    assert redirected_to(conn) == ~p"/register"
    assert get_session(conn, :return_to) == ~p"/schools/new"
  end
end
