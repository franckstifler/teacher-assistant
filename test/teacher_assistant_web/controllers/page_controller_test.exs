defmodule TeacherAssistantWeb.PageControllerTest do
  use TeacherAssistantWeb.ConnCase

  test "GET / renders the schools landing page", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Teacher Assistant"
    assert html =~ "Tout l&#39;établissement sur un seul tableau"
    # a school day role by role, the roles, Cameroon specifics and the pilot price
    for id <- ~w(journee bulletins roles terrain tarif questions),
        do: assert(html =~ ~s(id="#{id}"))

    assert html =~ "Gratuit pendant la phase pilote"
    # real screens of the app
    assert html =~ "/images/landing/roll-call.webp"
  end

  test "GET / speaks to schools only: no solo-teacher lane", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    refute html =~ "Enseignant seul"
    refute html =~ "je commence seul"
    refute html =~ "carnet"
    refute html =~ ~s(href="/register")
    refute html =~ ~s(id="portes")
  end

  test "GET / spares phones the desktop screenshots they never show", %{conn: conn} do
    pictures =
      conn
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("picture")

    for shot <- ~w(dash-desktop dash-desktop-light bulletins-desktop) do
      picture =
        Enum.find(
          pictures,
          &(LazyHTML.attribute(&1["img"], "src") == ["/images/landing/#{shot}.webp"])
        )

      assert [media] = picture |> LazyHTML.query("source") |> LazyHTML.attribute("media")
      assert media =~ "max-width"
    end
  end

  test "GET / links to every entry point the front door needs", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

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
