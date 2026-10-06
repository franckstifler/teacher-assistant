defmodule TeacherAssistantWeb.School.OfficialHeaderLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.Accounts
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  test "the head edits the lines and resets them", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#official-header-link")

    {:ok, view, _} = live(conn, ~p"/school/settings/header")
    assert render(view) =~ "République du Cameroun"

    view
    |> form("#header-lines-form", %{"lines" => "République du Cameroun\nPaix – Travail – Patrie\nDélégation X"})
    |> render_submit()

    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.official_header_lines == ["République du Cameroun", "Paix – Travail – Patrie", "Délégation X"]

    view |> element("#reset-header") |> render_click()
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.official_header_lines == nil
  end

  test "the head uploads a signature, served to members", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/settings/header")

    upload =
      file_input(view, "#signature-form", :signature, [
        %{name: "sig.png", content: File.read!("test/support/fixtures/files/1x1.png"), type: "image/png"}
      ])

    render_upload(upload, "sig.png")
    view |> form("#signature-form") |> render_submit()

    {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert is_binary(profile.signature_path)

    assert conn |> get(~p"/school/logo?kind=signature") |> response(200)
    assert conn |> get(~p"/school/logo?kind=stamp") |> response(404)
  end

  test "a Censeur is sent back to settings", %{workspace: ws, scope: scope} do
    censeur = TeacherFixtures.member_scope_fixture(scope, %{roles: [:vice_principal]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, censeur.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, ws.id)

    assert {:error, {:live_redirect, %{to: "/school/settings"}}} = live(conn, ~p"/school/settings/header")
  end
end
