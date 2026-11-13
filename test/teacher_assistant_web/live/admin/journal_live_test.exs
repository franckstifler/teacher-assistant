defmodule TeacherAssistantWeb.Admin.JournalLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Organization, Scope, TeacherFixtures}

  test "lists events and filters by action", %{conn: conn} do
    op = TeacherFixtures.admin_user_fixture()
    %{workspace: ws} = TeacherFixtures.school_fixture()
    {:ok, ws} = Organization.suspend_school(%Scope{current_user: op}, ws, "Impayé-#{ws.id}")
    {:ok, _} = Organization.set_modules(%Scope{current_user: op}, ws, [:notes])

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(op)

    {:ok, view, html} = live(conn, ~p"/admin/journal")
    assert html =~ "Impayé-#{ws.id}"

    view |> form("#journal-filter", %{"action" => "modules_changed"}) |> render_change()
    assert render(view) =~ "Modules modifiés"
    refute render(view) =~ "Impayé-#{ws.id}"
  end

  # A rename journals the old and new name as text, not as a list like modules.
  test "shows a member's rename, old name to new", %{conn: conn} do
    op = TeacherFixtures.admin_user_fixture()
    %{scope: head} = TeacherFixtures.setup_complete_school_fixture()
    m = TeacherFixtures.membership_fixture(head, %{roles: [:teacher]})
    {:ok, m} = Ash.load(m, :user, scope: head)
    before = m.user.name
    {:ok, _} = TeacherAssistant.Accounts.rename_member(head, m, "YEBONDJE Augustin")

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(op)

    {:ok, _view, html} = live(conn, ~p"/admin/journal")
    assert html =~ "#{before} → YEBONDJE Augustin"
  end

  test "a forged page number falls back to the first page", %{conn: conn} do
    op = TeacherFixtures.admin_user_fixture()

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(op)

    assert {:ok, _view, _html} = live(conn, ~p"/admin/journal?page=abc")
  end
end
