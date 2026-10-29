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

  test "GET /schools/start sends a signed-in user without a school to school setup", %{
    conn: conn
  } do
    conn =
      conn
      |> log_in_user(TeacherAssistant.TeacherFixtures.user_fixture())
      |> get(~p"/schools/start")

    assert redirected_to(conn) == ~p"/schools/new"
  end

  describe "a school member" do
    setup :register_and_log_in_user

    test "GET /schools/start sends them to their school, not a new one", %{conn: conn} do
      assert conn |> get(~p"/schools/start") |> redirected_to() == ~p"/school"
    end

    test "GET / offers their space instead of « Se connecter »", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(id="landing-my-space")
      assert html =~ ~s(href="/school")
      refute html =~ ~s(href="/sign-in")
    end
  end
end
