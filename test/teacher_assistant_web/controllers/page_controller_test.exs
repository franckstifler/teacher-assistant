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
    # school onboarding (the repositioned primary flow)
    assert html =~ ~s(href="/schools/new")
    # bilingual switch
    assert html =~ ~s(href="/locale/fr")
    assert html =~ ~s(href="/locale/en")
  end
end
