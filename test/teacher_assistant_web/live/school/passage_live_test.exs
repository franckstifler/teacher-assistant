defmodule TeacherAssistantWeb.School.PassageLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  test "settings links to the page, which shows the defaults", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#passage-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/passage")
    assert has_element?(view, "#passage-form input[name='passage[passage_min]'][value='10']")
    assert has_element?(view, "#passage-form input[name='passage[rachat_min]'][value='9.5']")

    assert has_element?(
             view,
             "#passage-form input[name='passage[exclusion_absence_hours]'][value='60']"
           )
  end

  test "saves the rules; an inconsistent set shows the error", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/passage")

    view
    |> form("#passage-form", %{passage: %{rachat_min: "9,75", exclusion_absence_hours: ""}})
    |> render_submit()

    assert render(view) =~ "Réglage enregistré."
    rules = Assessment.passage_rules(scope)
    assert Decimal.equal?(rules.rachat_min, Decimal.new("9.75"))
    assert rules.exclusion_absence_hours == nil

    view |> form("#passage-form", %{passage: %{rachat_min: "12"}}) |> render_submit()
    assert has_element?(view, "#passage-error", "Exclusion < rachat")
  end

  test "a plain teacher is sent back to settings", %{scope: scope} do
    other = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} =
             live(conn, ~p"/school/settings/passage")
  end
end
