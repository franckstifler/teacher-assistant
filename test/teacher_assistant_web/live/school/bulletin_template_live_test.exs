defmodule TeacherAssistantWeb.School.BulletinTemplateLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  test "settings links to the page, which shows the defaults and the header", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#bulletin-template-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/bulletin")
    assert has_element?(view, "#settings-form input[value='by_class'][checked]")
    assert has_element?(view, "#settings-form input[value='rank'][checked]")
    refute has_element?(view, "#settings-form input[value='qr_code'][checked]")
    assert has_element?(view, "#grade-scale-form input[value='A']")
    assert has_element?(view, "#header-preview", "République du Cameroun")
  end

  test "saves the language and elements, unchecking everything", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/bulletin")

    view
    |> form("#settings-form", %{bulletin: %{language: "bilingual", elements: [""]}})
    |> render_submit()

    assert render(view) =~ "Réglage enregistré."
    assert %{language: :bilingual, elements: []} = Assessment.bulletin_settings(scope)
  end

  test "edits the grade scale; a bad scale shows the error; reset restores the default",
       %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/bulletin")

    view |> element("#remove-grade-5") |> render_click()

    view
    |> form("#grade-scale-form", %{
      grades: %{
        "0" => %{from: "0", letter: "F", remark: "Fail"},
        "1" => %{from: "8", letter: "E", remark: "Weak"},
        "2" => %{from: "10", letter: "D", remark: "Pass"},
        "3" => %{from: "12", letter: "C", remark: "Good"},
        "4" => %{from: "15", letter: "B+", remark: "Very good"}
      }
    })
    |> render_submit()

    assert Assessment.bulletin_settings(scope).custom_scale?
    assert List.last(Assessment.bulletin_settings(scope).grade_scale).letter == "B+"

    view
    |> form("#grade-scale-form", %{grades: %{"0" => %{from: "2", letter: "F", remark: "Fail"}}})
    |> render_submit()

    assert has_element?(view, "#scale-error", "La première tranche doit commencer à 0.")

    view |> element("#reset-grades") |> render_click()
    refute Assessment.bulletin_settings(scope).custom_scale?
  end

  test "a plain teacher is sent back to settings", %{scope: scope} do
    other = TeacherFixtures.member_scope_fixture(scope)

    conn =
      build_conn()
      |> log_in_user(other.current_user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} =
             live(conn, ~p"/school/settings/bulletin")
  end
end
