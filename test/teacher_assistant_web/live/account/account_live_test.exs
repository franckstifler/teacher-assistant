defmodule TeacherAssistantWeb.Account.AccountLiveTest do
  @moduledoc "« Mon compte » (A9)."
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.TeacherFixtures

  describe "a member of a school" do
    setup :register_and_log_in_user

    test "sees their identity and why they cannot delete the account", %{conn: conn, actor: head} do
      {:ok, view, _} = live(conn, ~p"/account")
      assert has_element?(view, "#account-identity", to_string(head.email))
      assert has_element?(view, "#account-schools")
      assert has_element?(view, "#account-delete", "chef d'établissement")
      refute has_element?(view, "#account-delete button")
      assert has_element?(view, ~s(#account-password[href="/account/password"]))
    end

    test "the rail links to Mon compte", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/school")
      assert has_element?(view, ~s(#rail-account[href="/account"]))
    end
  end

  test "a user without school deletes their account and sees it confirmed on the sign-in page" do
    user = TeacherFixtures.user_fixture()
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user)
    {:ok, view, _} = live(conn, ~p"/account")

    view |> element("#account-delete button") |> render_click()
    assert {"/sign-in", %{"info" => "Compte supprimé."}} = assert_redirect(view)

    assert Ash.get!(TeacherAssistant.Accounts.User, user.id, authorize?: false).email == nil
  end

  test "an operator acting as a member cannot open it" do
    %{workspace: ws, head_user: head} = TeacherFixtures.setup_complete_school_fixture()
    op = TeacherFixtures.admin_user_fixture()

    conn =
      Phoenix.ConnTest.build_conn()
      |> log_in_user(op)
      |> Plug.Conn.put_session(
        :impersonation,
        TeacherAssistantWeb.Impersonation.session_value(
          head.id,
          ws.id,
          nil,
          System.os_time(:second)
        )
      )
      |> Plug.Conn.put_session(:workspace_id, ws.id)

    assert {:error, {_, %{to: _}}} = live(conn, ~p"/account")
  end
end
