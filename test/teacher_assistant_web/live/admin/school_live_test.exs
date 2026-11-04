defmodule TeacherAssistantWeb.Admin.SchoolLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ecto.Query, only: [from: 2]
  alias TeacherAssistant.{Accounts, Operator, Scope, TeacherFixtures}

  setup %{conn: conn} do
    %{workspace: ws, head_user: head} = TeacherFixtures.school_fixture()
    op = TeacherFixtures.admin_user_fixture()

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(op)

    %{conn: conn, ws: ws, head: head, op: %Scope{current_user: op}}
  end

  test "verifies the school", %{conn: conn, ws: ws, head: head} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    view |> element("#verify-school") |> render_click()
    {:ok, p} = Accounts.fetch_school_profile(school_scope(head, ws))
    assert p.verification_status == :verified
  end

  test "each member can be opened as", %{conn: conn, ws: ws, head: head} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    assert has_element?(view, "#impersonate-#{head.id}[data-method=post]")
  end

  test "saves modules", %{conn: conn, ws: ws, op: op} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    view |> form("#modules-form", %{"modules" => ["notes", "photos"]}) |> render_submit()
    {:ok, %{workspace: ws}} = Operator.get_school(op, ws.id)
    assert ws.modules == [:notes, :photos]
  end

  test "saving with every box unchecked clears the modules", %{conn: conn, ws: ws, op: op} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    view |> render_submit("save_modules", %{"modules" => [""]})
    {:ok, %{workspace: ws}} = Operator.get_school(op, ws.id)
    assert ws.modules == []
  end

  test "suspends with a reason, then reactivates", %{conn: conn, ws: ws, op: op} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    assert has_element?(view, "#suspend-impact", "membre perd l'accès")
    refute has_element?(view, "#suspend-form")
    view |> element("#suspend-school") |> render_click()
    view |> form("#suspend-form", %{"reason" => "Impayé"}) |> render_submit()
    refute has_element?(view, "#suspend-modal")
    assert has_element?(view, "#school-suspended-badge")
    view |> element("#reactivate-school") |> render_click()
    refute has_element?(view, "#school-suspended-badge")

    assert [:school_reactivated, :school_suspended | _] =
             op |> Accounts.list_audit_events(workspace_id: ws.id) |> Enum.map(& &1.action)
  end

  test "an empty reason is refused", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    view |> element("#suspend-school") |> render_click()
    html = view |> form("#suspend-form", %{"reason" => " "}) |> render_submit()
    assert html =~ "motif"
    refute has_element?(view, "#school-suspended-badge")
  end

  test "resets a member's password and shows it once", %{conn: conn, ws: ws, head: head} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    view |> element("#reset-user-#{head.id}") |> render_click()
    view |> element("#reset-confirm") |> render_click()
    assert has_element?(view, "#reset-password-value")
    view |> element("#reset-close") |> render_click()
    refute has_element?(view, "#reset-password-value")
  end

  test "status, meta line and modules' 30-day use", %{conn: conn, ws: ws} do
    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    assert has_element?(view, "#school-back[href='/admin/schools']")
    assert has_element?(view, "#school-verification", "À vérifier")
    assert has_element?(view, "#school-meta", "1 membre")
    assert has_element?(view, "#school-meta", "aucune saisie")
    assert has_element?(view, "#module-use-notes", "inutilisé")
    refute has_element?(view, "#module-use-emploi_du_temps", "30 j")

    view |> element("#verify-school") |> render_click()
    assert has_element?(view, "#school-verification", "Vérifié le")
    refute has_element?(view, "#school-verify")
  end

  test "searches members by name or phone, and filters temporary passwords", %{
    conn: conn,
    ws: ws,
    head: head
  } do
    scope = school_scope(head, ws)
    teacher = TeacherAssistant.TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    t = teacher.current_user
    t_id = Ecto.UUID.dump!(t.id)

    TeacherAssistant.Repo.update_all(
      from(u in "users", where: u.id == ^t_id),
      set: [must_change_password: true, phone: "+237677001122", name: "Zoé Mbarga"]
    )

    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}")
    assert has_element?(view, "#filter-temp", "1")

    view |> form("#member-search", %{"q" => "77 00 11"}) |> render_change()
    assert has_element?(view, "#member-#{t.id}")
    refute has_element?(view, "#member-#{head.id}")

    view |> form("#member-search", %{"q" => "zoé"}) |> render_change()
    assert has_element?(view, "#member-#{t.id}")

    {:ok, view, _html} = live(conn, ~p"/admin/schools/#{ws.id}?temp=1")
    assert has_element?(view, "#member-#{t.id}", "Mot de passe temporaire")
    refute has_element?(view, "#member-#{head.id}")
  end

  test "an unknown school goes back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/schools"}}} =
             live(conn, ~p"/admin/schools/#{Ecto.UUID.generate()}")
  end
end
