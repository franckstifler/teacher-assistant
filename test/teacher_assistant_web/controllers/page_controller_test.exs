defmodule TeacherAssistantWeb.PageControllerTest do
  use TeacherAssistantWeb.ConnCase

  defp landing(conn), do: conn |> get(~p"/") |> html_response(200)

  defp doc(html), do: LazyHTML.from_document(html)

  defp hrefs(doc, selector),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute("href")

  test "GET / renders the schools landing page, section by section", %{conn: conn} do
    html = landing(conn)
    doc = doc(html)

    assert html =~ "Teacher Assistant"
    assert [_] = doc |> LazyHTML.query("h1") |> Enum.to_list()
    assert LazyHTML.text(doc["h1"]) =~ "Tout l'établissement, sur le téléphone de chacun."

    for id <- ~w(contenu sequence bulletins roles tarif questions),
        do: assert(html =~ ~s(id="#{id}"))

    # the header nav (and its phone menu) point at the sections
    for anchor <- ~w(#sequence #roles #tarif #questions),
        do: assert(anchor in hrefs(doc, ~s(header nav a)))

    # one sequence in four steps, the four role cards, three start steps, four questions
    assert doc |> LazyHTML.query("#sequence ol > li") |> Enum.count() == 4
    assert doc |> LazyHTML.query("#roles article") |> Enum.count() == 4
    assert doc |> LazyHTML.query("#tarif ol > li") |> Enum.count() == 3
    assert doc |> LazyHTML.query("#questions details") |> Enum.count() == 4

    assert html =~ "Phase pilote 2026-2027"
    assert html =~ "Gratuit pendant la phase pilote"
    assert html =~ "Votre établissement, prêt pour la prochaine séquence."
  end

  test "GET / draws the app instead of shipping screenshots", %{conn: conn} do
    html = landing(conn)
    doc = doc(html)

    refute html =~ "/images/landing/"
    assert doc |> LazyHTML.query("main img") |> Enum.count() == 0
    # the drawings are decorative: the hero art and the printed bulletin
    assert doc |> LazyHTML.query(~s(main [aria-hidden="true"])) |> Enum.count() >= 2
  end

  test "GET / says only what the app does: no placeholders, no promises", %{conn: conn} do
    html = landing(conn)

    for placeholder <- ["[N]", "[délai]", "[Réponse", "séquence 3"],
        do: refute(html =~ placeholder)

    # no automatic council planner, publication does not notify families, no printed codes
    refute html =~ "Calendrier des conseils proposé"
    refute html =~ "familles prévenues"
    refute html =~ "code imprimé"
    refute html =~ "Que se passe-t-il après la phase pilote"
  end

  test "GET / speaks to schools only: no solo-teacher lane", %{conn: conn} do
    html = landing(conn)

    refute html =~ "Enseignant seul"
    refute html =~ "je commence seul"
    refute html =~ "carnet"
    refute html =~ ~s(href="/register")
    refute html =~ ~s(id="portes")
  end

  test "GET / links to every entry point the front door needs", %{conn: conn} do
    doc = conn |> landing() |> doc()

    assert hrefs(doc, ~s(a[href="#contenu"])) == ["#contenu"]
    # the header, the hero, the price card and the closing band all enrol a school
    assert doc |> LazyHTML.query(~s(a[href="/schools/start"])) |> Enum.count() >= 4
    assert "/schools/start" in hrefs(doc, "header a")
    assert "/sign-in" in hrefs(doc, "header a")

    hero = LazyHTML.query(doc, ~s(section[aria-labelledby="landing-title"]))
    assert LazyHTML.text(hero) =~ "Je suis enseignant : me connecter"
    assert hrefs(hero, "a") == ["/schools/start", "/sign-in"]

    # bilingual switch
    assert "/locale/fr" in hrefs(doc, "header a")
    assert "/locale/en" in hrefs(doc, "header a")
    refute doc |> LazyHTML.query("#landing-my-space") |> Enum.any?()
  end

  test "GET / phone menu is a native disclosure with the sections and the language", %{
    conn: conn
  } do
    menu = conn |> landing() |> doc() |> LazyHTML.query("details#landing-menu")

    assert LazyHTML.text(menu["summary"]) =~ "Menu"

    for href <- ~w(#sequence #roles #tarif #questions /locale/fr /locale/en),
        do: assert(href in hrefs(menu, "a"))
  end

  test "GET / in English reads in English", %{conn: conn} do
    html = conn |> init_test_session(%{locale: "en"}) |> landing()

    assert html =~ "The whole school, on everyone&#39;s phone."
    assert html =~ "One sequence, from roll call to report card"
    assert html =~ "I&#39;m a teacher: sign in"
    assert html =~ "Free during the pilot phase"
    assert html =~ "Report cards ready to print, in the official format."
    refute html =~ "Tout l&#39;établissement"
    refute html =~ "Inscrire mon établissement"
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
      html = landing(conn)
      doc = doc(html)

      assert html =~ ~s(id="landing-my-space")
      assert "/school" in hrefs(doc, "header a")
      refute html =~ ~s(href="/sign-in")
      refute html =~ "Je suis enseignant : me connecter"

      hero = LazyHTML.query(doc, ~s(section[aria-labelledby="landing-title"]))
      assert hrefs(hero, "a") == ["/schools/start", "/school"]
    end
  end
end
