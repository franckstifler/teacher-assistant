defmodule TeacherAssistantWeb.SchoolInvitationControllerTest do
  use TeacherAssistantWeb.ConnCase, async: true
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures
  setup :register_and_log_in_user

  test "accepting a matching invitation joins the school", %{conn: conn, actor: user} do
    head = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "École Accept"
      })

    head_scope = school_scope(head, school)

    {:ok, inv} =
      Accounts.invite_member(head_scope, %{email: to_string(user.email), roles: [:teacher]})

    conn = post(conn, ~p"/schools/invitations/#{inv.token}/accept")
    assert redirected_to(conn) == "/school"
    assert {:ok, _m} = Accounts.fetch_school_membership(head_scope, user)
  end

  test "a mismatched invitation is rejected", %{conn: conn} do
    head = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "École Mismatch"
      })

    head_scope = school_scope(head, school)

    {:ok, inv} =
      Accounts.invite_member(head_scope, %{email: "someone@example.com", roles: [:teacher]})

    conn = post(conn, ~p"/schools/invitations/#{inv.token}/accept")
    assert redirected_to(conn) == "/school"

    refute match?(
             {:ok, _},
             Accounts.fetch_school_membership(head_scope, conn.assigns.current_user)
           )
  end

  describe "show/2 — signed-out visitor" do
    test "is offered register + sign-in and return_to is set", %{conn: _conn} do
      %{workspace: _ws, head_user: _head, scope: head_scope} = TeacherFixtures.school_fixture()

      {:ok, inv} =
        Accounts.invite_member(head_scope, %{email: "new@example.com", roles: [:teacher]})

      conn =
        build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> get(~p"/schools/invitations/#{inv.token}")

      html = html_response(conn, 200)
      assert html =~ ~p"/register"
      assert html =~ ~p"/sign-in"
      assert get_session(conn, :return_to) == ~p"/schools/invitations/#{inv.token}"
    end
  end

  describe "show/2 — signed-in visitor" do
    test "matching email sees a Join action", %{conn: _conn} do
      %{scope: head_scope} = TeacherFixtures.school_fixture()

      {:ok, inv} =
        Accounts.invite_member(head_scope, %{email: "match@example.com", roles: [:teacher]})

      user = TeacherFixtures.user_fixture(%{email: "match@example.com"})

      conn =
        build_conn()
        |> log_in_user(user)
        |> get(~p"/schools/invitations/#{inv.token}")

      html = html_response(conn, 200)
      assert html =~ "accept-invitation-form"
      assert html =~ ~p"/schools/invitations/#{inv.token}/accept"
    end

    test "mismatched email is told to sign out, with no accept action offered", %{conn: _conn} do
      %{scope: head_scope} = TeacherFixtures.school_fixture()

      {:ok, inv} =
        Accounts.invite_member(head_scope, %{email: "match@example.com", roles: [:teacher]})

      other = TeacherFixtures.user_fixture(%{email: "other@example.com"})

      conn =
        build_conn()
        |> log_in_user(other)
        |> get(~p"/schools/invitations/#{inv.token}")

      html = html_response(conn, 200)
      assert html =~ "match@example.com"
      refute html =~ ~p"/schools/invitations/#{inv.token}/accept"
    end
  end

  describe "register-from-invite" do
    test "a signed-out visitor who registers lands back on the invite page and can join", %{
      conn: _conn
    } do
      %{scope: head_scope} = TeacherFixtures.school_fixture()

      {:ok, inv} =
        Accounts.invite_member(head_scope, %{email: "invitee@example.com", roles: [:teacher]})

      # 1. Signed-out visit stores return_to in the session (as AuthController.success/4
      #    expects to find it once the person finishes registering).
      conn =
        build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> get(~p"/schools/invitations/#{inv.token}")

      return_to = get_session(conn, :return_to)
      assert return_to == ~p"/schools/invitations/#{inv.token}"

      # 2. Registration completes (mirrors what AshAuthentication.Phoenix.Controller's
      #    `store_in_session/2` does: put the new user's id in the session). The conn
      #    from the GET above has already been sent, so recycle it (fresh conn, same
      #    session cookie) before making another request, then carry `return_to`
      #    forward the way a real signed cookie session would.
      new_user = TeacherFixtures.user_fixture(%{email: "invitee@example.com"})

      conn =
        conn
        |> recycle()
        |> log_in_user(new_user)
        |> put_session(:return_to, return_to)

      # 3. Back on the invite page (as the post-auth redirect would land them), the
      #    matching branch now offers Join.
      conn = get(conn, ~p"/schools/invitations/#{inv.token}")
      html = html_response(conn, 200)
      assert html =~ "accept-invitation-form"

      # 4. Join creates the membership with the invited roles and marks the invitation
      #    accepted.
      conn = post(conn, ~p"/schools/invitations/#{inv.token}/accept")
      assert redirected_to(conn) == "/school"

      assert {:ok, membership} = Accounts.fetch_school_membership(head_scope, new_user)
      assert membership.roles == [:teacher]

      assert {:ok, accepted_inv} = Accounts.fetch_invitation_by_token(inv.token)
      assert accepted_inv.status == :accepted
    end
  end

  test "accepting while signed out redirects to sign-in and remembers the link", %{conn: _conn} do
    %{scope: head_scope} = TeacherAssistant.TeacherFixtures.school_fixture()

    {:ok, inv} =
      TeacherAssistant.Accounts.invite_member(head_scope, %{
        email: "new@example.com",
        roles: [:teacher]
      })

    conn =
      build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post(~p"/schools/invitations/#{inv.token}/accept")

    assert redirected_to(conn) == ~p"/sign-in"
    assert get_session(conn, :return_to) == ~p"/schools/invitations/#{inv.token}"
  end

  test "the invitation page shows the school name to a signed-out visitor", %{conn: conn} do
    %{workspace: ws, scope: head} = TeacherAssistant.TeacherFixtures.school_fixture()

    {:ok, inv} =
      TeacherAssistant.Accounts.invite_member(head, %{email: "v@example.com", roles: [:teacher]})

    html = conn |> get(~p"/schools/invitations/#{inv.token}") |> html_response(200)
    assert html =~ ws.name
  end
end
