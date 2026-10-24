defmodule TeacherAssistantWeb.School.AppreciationsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Accounts, Assessment, Organization}
  alias TeacherAssistant.Academics.Appreciations

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{name: "Lycée A"})

    scope = school_scope(user, school)
    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)
    _year = TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, scope: scope, school: school}
  end

  test "settings links to the page, which shows the default scale and thresholds", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#appreciations-link")

    {:ok, view, html} = live(conn, ~p"/school/settings/appreciations")
    assert html =~ "Très insuffisant"
    assert html =~ "Excellent"
    assert has_element?(view, "#band-7-label")
    refute has_element?(view, "#band-7-to")

    assert has_element?(
             view,
             "#distinctions-form input[name='distinctions[felicitations_min]'][value='16']"
           )
  end

  test "restoring the default scale asks first", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")
    assert has_element?(view, "#reset-bands[data-confirm]")
  end

  test "test a mark against the scale being edited", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")
    view |> form("#band-test-form", %{test: "13,5"}) |> render_change()
    assert render(element(view, "#band-test-result")) =~ "Assez bien"
  end

  test "non-numbers in the editor are ignored, not crashed on", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")
    view |> form("#band-test-form", %{test: "NaN"}) |> render_change()
    assert render(element(view, "#band-test-result")) =~ "—"

    view |> form("#bands-form", %{"bands" => %{"0" => %{"to" => "1e999"}}}) |> render_change()
    assert render(element(view, "#bands-form")) =~ "1e999"

    view |> form("#bands-form", %{"bands" => %{"0" => %{"to" => "inf"}}}) |> render_change()
    view |> element("#save-settings") |> render_click()
    assert render(element(view, "#bands-error")) =~ "9,5"

    view
    |> form("#distinctions-form", %{"distinctions" => %{"felicitations_min" => "NaN"}})
    |> render_submit()

    assert render(element(view, "#distinctions-error")) =~ "9,5"
  end

  test "edit, split, remove and save the scale", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")

    view |> element("#remove-band-0") |> render_click()
    view |> element("#split-last-band") |> render_click()

    view
    |> form("#bands-form", %{"bands" => %{"7" => %{"label" => "Remarquable"}}})
    |> render_change()

    view |> element("#save-settings") |> render_click()
    assert render(view) =~ "Barème enregistré."

    labels = Assessment.grading_rules(scope) |> Appreciations.bands() |> Enum.map(& &1.label)
    # first band removed (now "Insuffisant" starts at 0), last split in two
    assert hd(labels) == "Insuffisant"
    assert length(labels) == 8
    assert "Remarquable" in labels
  end

  test "an invalid scale is refused with a message and nothing is saved", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")

    view
    |> form("#bands-form", %{"bands" => %{"0" => %{"to" => "12"}, "1" => %{"to" => "9"}}})
    |> render_change()

    view |> element("#save-settings") |> render_click()
    assert render(element(view, "#bands-error")) =~ "croissantes"
    assert {:ok, %{appreciation_bands: bands}} = Accounts.fetch_school_profile(scope)
    assert bands in [nil, []]
  end

  test "thresholds and toggles save; a bad order shows an error", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")

    view
    |> form("#distinctions-form", %{
      "distinctions" => %{
        "felicitations_min" => "17",
        "blame_travail_below" => "",
        "distinctions_require_conduct?" => "true"
      }
    })
    |> render_submit()

    assert render(view) =~ "Réglage enregistré."
    rules = Assessment.grading_rules(scope)
    assert Decimal.equal?(rules.felicitations_min, 17)
    assert rules.blame_travail_below == nil
    assert rules.distinctions_require_conduct?

    view
    |> form("#distinctions-form", %{"distinctions" => %{"encouragements_min" => "19"}})
    |> render_submit()

    assert render(element(view, "#distinctions-error")) =~ "Félicitations"
  end

  test "reset goes back to the default scale", %{conn: conn, scope: scope} do
    {:ok, _} =
      Assessment.update_appreciation_bands(scope, [
        %{from: "0", label: "X"},
        %{from: "10", label: "Y"}
      ])

    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")
    view |> element("#reset-bands") |> render_click()
    assert render(view) =~ "Très insuffisant"
    assert Assessment.grading_rules(scope) |> Appreciations.bands() |> length() == 8
  end

  test "saved labels show as typed in English", %{conn: conn, scope: scope} do
    {:ok, _} =
      Assessment.update_appreciation_bands(scope, [
        %{from: "0", label: "Faible"},
        %{from: "10", label: "Admis"}
      ])

    conn = get(conn, ~p"/locale/en")
    {:ok, _view, html} = live(conn, ~p"/school/settings/appreciations")
    assert html =~ "Faible"
    assert html =~ "Admis"
  end

  test "a plain teacher cannot open the page", %{scope: scope, school: school} do
    teacher = TeacherAssistant.TeacherFixtures.user_fixture()

    TeacherAssistant.TeacherFixtures.membership_fixture(scope, %{user: teacher, roles: [:teacher]})

    teacher_conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(teacher)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} =
             live(teacher_conn, ~p"/school/settings/appreciations")
  end

  test "the APC preset fills five coded bands, saved with the bar", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")

    view |> element("#apc-preset") |> render_click()
    assert has_element?(view, "#band-0-code[value='CNA']")
    assert has_element?(view, "#band-4-code[value='CTBA']")
    refute has_element?(view, "#band-5-label")
    assert has_element?(view, "#band-0-to[value='10']")

    view |> element("#save-settings") |> render_click()

    bands = Assessment.grading_rules(scope).appreciation_bands
    assert Enum.map(bands, & &1.code) == ~w(CNA CMA CA CBA CTBA)
    assert List.last(bands).label == "C. très bien acquise"
  end

  test "a band's code is editable", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/appreciations")

    view
    |> form("#bands-form", %{bands: %{"0" => %{"code" => "TI"}}})
    |> render_change()

    view |> element("#save-settings") |> render_click()
    assert hd(Assessment.grading_rules(scope).appreciation_bands).code == "TI"
  end
end
