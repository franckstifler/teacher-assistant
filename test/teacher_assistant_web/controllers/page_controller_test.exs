defmodule TeacherAssistantWeb.PageControllerTest do
  use TeacherAssistantWeb.ConnCase

  defp landing(conn), do: conn |> get(~p"/") |> html_response(200)

  defp doc(html), do: LazyHTML.from_document(html)

  defp hrefs(doc, selector),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute("href")

  test "GET / renders the schools landing page, section by section", %{conn: conn} do
    html = landing(conn)
    doc = doc(html)

    assert html =~ "Scolaka"
    assert [_] = doc |> LazyHTML.query("h1") |> Enum.to_list()
    assert LazyHTML.text(doc["h1"]) =~ "Tout l'établissement, sur le téléphone de chacun."

    for id <- ~w(contenu sequence bulletins frais inclus roles tarif questions),
        do: assert(html =~ ~s(id="#{id}"))

    # the header nav (and its phone menu) point at the sections
    for anchor <- ~w(#sequence #frais #inclus #tarif #questions),
        do: assert(anchor in hrefs(doc, ~s(header nav a)))

    # one sequence in four steps, the four role cards, three start steps, four questions
    assert doc |> LazyHTML.query("#sequence ol > li") |> Enum.count() == 4
    assert doc |> LazyHTML.query("#roles article") |> Enum.count() == 4
    assert doc |> LazyHTML.query("#tarif ol > li") |> Enum.count() == 3
    assert doc |> LazyHTML.query("#questions details") |> Enum.count() == 5
    assert html =~ "ne fonctionne pas hors ligne"
    assert html =~ "installation accompagnée"
    # fees get their own section, and every module is listed once
    assert doc |> LazyHTML.query("#frais ul > li") |> Enum.count() == 4
    assert doc |> LazyHTML.query("#inclus ul > li") |> Enum.count() == 8

    assert html =~ "Phase pilote 2026-2027"
    assert html =~ "Les bulletins sont prêts le soir du conseil de classe."
    assert html =~ "Gratuit pendant la phase pilote"
    assert html =~ "Votre établissement, prêt pour la prochaine séquence."
  end

  test "GET / draws the app instead of shipping screenshots", %{conn: conn} do
    html = landing(conn)
    doc = doc(html)

    refute html =~ "/images/landing/"
    assert doc |> LazyHTML.query("main img") |> Enum.count() == 0
    # the drawings are decorative: the hero art, the printed bulletin and the receipt
    assert doc |> LazyHTML.query(~s(main [aria-hidden="true"])) |> Enum.count() >= 3
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
    assert ["/schools/start", "/sign-in", "https://wa.me/" <> _] = hrefs(hero, "a")

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

    for href <- ~w(#sequence #frais #inclus #tarif #questions /locale/fr /locale/en),
        do: assert(href in hrefs(menu, "a"))
  end

  test "GET / carries a meta description, in the visitor's language", %{conn: conn} do
    description = fn conn ->
      conn
      |> landing()
      |> doc()
      |> LazyHTML.query(~s(meta[name="description"]))
      |> LazyHTML.attribute("content")
    end

    assert [fr] = description.(conn)
    assert fr =~ "Tout l'établissement, sur le téléphone de chacun. L'appel, les notes"

    assert [en] = conn |> init_test_session(%{locale: "en"}) |> description.()
    assert en =~ "The whole school, on everyone's phone. "
  end

  test "GET / has a page title that says what Scolaka is, in the visitor's language", %{
    conn: conn
  } do
    title = fn conn ->
      conn |> landing() |> doc() |> LazyHTML.query("title") |> LazyHTML.text()
    end

    assert title.(conn) == "Scolaka · Gestion scolaire au Cameroun"

    assert conn |> init_test_session(%{locale: "en"}) |> title.() ==
             "Scolaka · School management in Cameroon"
  end

  describe "privacy page" do
    test "GET /confidentialite says what is kept, who sees it and where", %{conn: conn} do
      html = conn |> get(~p"/confidentialite") |> html_response(200)
      doc = doc(html)

      assert LazyHTML.text(doc["h1"]) =~ "Les données de votre établissement"

      for heading <- [
            "Ce que nous gardons",
            "Qui peut les voir",
            "Où elles se trouvent",
            "Cookies",
            "Consulter, corriger ou supprimer"
          ],
          do: assert(LazyHTML.text(doc["main h2"]) =~ heading)

      # the services that handle data are named, and the support access is disclosed
      for name <- ["Hetzner", "Cloudflare", "Brevo"], do: assert(html =~ name)
      assert html =~ "limité à une heure et inscrit dans un journal"
      assert "mailto:contact@example.test" in hrefs(doc, "main a")
      assert "/" in hrefs(doc, "header a")
    end

    test "GET /confidentialite reads in English", %{conn: conn} do
      html =
        conn
        |> init_test_session(%{locale: "en"})
        |> get(~p"/confidentialite")
        |> html_response(200)

      assert html =~ "What we keep"
      refute html =~ "Ce que nous gardons"
    end

    test "the landing's footer links to it", %{conn: conn} do
      doc = conn |> landing() |> doc()
      assert "/confidentialite" in hrefs(doc, "footer a")
    end
  end

  describe "contact links" do
    test "GET / offers a demo and questions on WhatsApp, and the e-mail", %{conn: conn} do
      html = landing(conn)
      doc = doc(html)

      # the hero asks for a demonstration, with the message already typed
      assert [demo] = hrefs(doc, "#landing-demo")
      assert demo =~ "https://wa.me/237600000001?text="
      assert URI.decode(demo) =~ "je souhaite une démonstration de Scolaka"

      # the price card, the closing band and the footer all reach us
      wa = Enum.filter(hrefs(doc, "a"), &String.starts_with?(&1, "https://wa.me/"))
      assert length(wa) >= 4
      assert LazyHTML.text(doc["#landing-contact"]) =~ "+237 600 00 00 01"
      assert "mailto:contact@example.test" in hrefs(doc, "a")
      assert html =~ "Écrivez-nous sur WhatsApp"
    end

    test "GET / hides a contact that is not set", %{conn: conn} do
      previous = Application.get_env(:teacher_assistant, :contact)
      on_exit(fn -> Application.put_env(:teacher_assistant, :contact, previous) end)

      Application.put_env(:teacher_assistant, :contact, whatsapp: "+237 600 00 00 01", email: "")
      html = landing(conn)
      assert html =~ "wa.me"
      refute html =~ "mailto:"

      Application.put_env(:teacher_assistant, :contact, whatsapp: nil, email: nil)
      html = landing(conn)
      refute html =~ "wa.me"
      refute html =~ ~s(id="landing-demo")
      refute html =~ ~s(id="landing-contact")
      refute html =~ "Une question ?"
    end
  end

  test "GET / in English reads in English", %{conn: conn} do
    html = conn |> init_test_session(%{locale: "en"}) |> landing()

    assert html =~ "The whole school, on everyone&#39;s phone."
    assert html =~ "One sequence, from roll call to report card"
    assert html =~ "I&#39;m a teacher: sign in"
    assert html =~ "Free during the pilot phase"
    assert html =~ "Report cards ready to print, in the official format."
    assert html =~ "Every franc collected has its receipt, and every receipt can be checked."
    assert html =~ "Everything included"
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
      assert ["/schools/start", "/school", "https://wa.me/" <> _] = hrefs(hero, "a")
    end
  end
end
