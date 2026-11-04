defmodule TeacherAssistantWeb.School.SettingsHubTest do
  @moduledoc "The Paramètres hub: grouped rows, the pinned « À compléter », the search."
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Fees, Organization}

  setup :register_and_log_in_user

  test "a count of zero reads « 0 salle », never « 1 salle »", %{conn: conn, scope: scope} do
    assert Organization.list_rooms(scope) == []
    {:ok, view, _} = live(conn, ~p"/school/settings")

    assert has_element?(view, "#rooms-link", "0 salle")
    refute has_element?(view, "#rooms-link", "1 salle")
  end

  test "rows are grouped Calendrier / Notes et bulletins / Vie scolaire et organisation",
       %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")

    assert has_element?(view, "#settings-group-calendar #hub-year")
    assert has_element?(view, "#settings-group-calendar #holidays-link")
    assert has_element?(view, "#settings-group-calendar #periods-link")
    assert has_element?(view, "#settings-group-grades #coefficients-link")
    assert has_element?(view, "#settings-group-grades #hub-subjects")
    assert has_element?(view, "#settings-group-life #school-life-link")
    assert has_element?(view, "#settings-group-life #rooms-link")
    assert has_element?(view, "#settings-group-life #roles-link")
    assert has_element?(view, "#settings-group-life #assignments-link")
    # « Nouvelle année » is on the hub while the year is open
    assert has_element?(
             view,
             "#settings-group-life #new-year-link[href='/school/settings/new-year']"
           )

    # the year row states its séquences
    assert has_element?(view, "#hub-year", "séquences")
  end

  test "« À compléter » gathers the profile and the fees without types", %{conn: conn} = ctx do
    year = Organization.current_academic_year(ctx.scope)
    assert Fees.list_fee_types(ctx.scope, year) == []

    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#settings-todo", "À compléter")
    assert has_element?(view, "#settings-todo #todo-fees a[href='/school/settings/fees']")
    assert has_element?(view, "#settings-todo #todo-fees", "Aucun type de frais")

    {:ok, _} = Fees.create_default_fee_types(ctx.scope, year)
    {:ok, view, _} = live(conn, ~p"/school/settings")
    refute has_element?(view, "#todo-fees")
  end

  test "the search keeps the matching rows only", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")

    view |> form("#settings-search", %{"q" => "coefficient"}) |> render_change()
    assert has_element?(view, "#coefficients-link")
    refute has_element?(view, "#rooms-link")
    refute has_element?(view, "#settings-group-calendar")

    # accent- and case-insensitive
    view |> form("#settings-search", %{"q" => "SALLE"}) |> render_change()
    assert has_element?(view, "#rooms-link")
    refute has_element?(view, "#coefficients-link")

    view |> form("#settings-search", %{"q" => "zzzz"}) |> render_change()
    assert has_element?(view, "#settings-no-match")

    view |> form("#settings-search", %{"q" => ""}) |> render_change()
    assert has_element?(view, "#coefficients-link")
    assert has_element?(view, "#rooms-link")
  end
end
