defmodule TeacherAssistantWeb.PageControllerTest do
  use TeacherAssistantWeb.ConnCase

  test "GET / renders the landing page with both audience lanes", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Teacher Assistant"
    assert html =~ ~s(id="landing-hero")
    # the school is the primary product, but teachers keep a first-class lane
    assert html =~ ~s(id="school-lane")
    assert html =~ ~s(id="teacher-lane")
    # a real getting-started sequence
    assert html =~ ~s(id="start")
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
