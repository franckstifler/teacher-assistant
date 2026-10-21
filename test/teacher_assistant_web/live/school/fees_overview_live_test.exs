defmodule TeacherAssistantWeb.School.FeesOverviewLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import TeacherAssistant.FeesFixtures

  alias TeacherAssistant.{Fees, Organization, TeacherFixtures}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    year = Organization.current_academic_year(scope)
    ctx = fees_setup(%{scope | current_academic_year: year}, year)

    s =
      ctx.student
      |> Ash.Changeset.for_update(:update, %{matricule: "MAT-0042"}, scope: ctx.scope)
      |> Ash.update!()

    Map.put(ctx, :student, s)
  end

  defp conn_for(scope, user),
    do:
      build_conn()
      |> log_in_user(user)
      |> Plug.Conn.put_session(:workspace_id, scope.current_workspace.id)

  test "a teacher is redirected", ctx do
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn_for(ctx.scope, teacher.current_user), ~p"/school/fees")
  end

  test "recovery figures and the class table", %{conn: conn} = ctx do
    {:ok, _} = Fees.record_payment(ctx.scope, ctx.e, cash(30_000))
    {:ok, view, _} = live(conn, ~p"/school/fees")
    assert has_element?(view, "#recovery-collected", "30 000")
    assert has_element?(view, "#recovery-expected", "60 000")
    assert has_element?(view, "#recovery-class-#{ctx.cg.id}", "50 %")

    assert has_element?(
             view,
             "#recovery-class-#{ctx.cg.id} a[href='/school/classes/#{ctx.cg.id}/fees']"
           )
  end

  test "search by name and by matricule links to the student card", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/fees")
    href = "/school/classes/#{ctx.cg.id}/fees?student=#{ctx.e.id}"

    view |> form("#fee-search", %{q: "awa"}) |> render_change()
    assert has_element?(view, "#search-results a[href='#{href}']", "Awa A")

    view |> form("#fee-search", %{q: "MAT-0042"}) |> render_change()
    assert has_element?(view, "#search-results a[href='#{href}']")

    view |> form("#fee-search", %{q: "a"}) |> render_change()
    refute has_element?(view, "#search-results a")
    refute has_element?(view, "#search-empty")

    view |> form("#fee-search", %{q: "zzzz"}) |> render_change()
    assert has_element?(view, "#search-empty", "Aucun élève trouvé.")
  end

  test "recent payments list numbers linking to the receipt", %{conn: conn} = ctx do
    {:ok, p} = Fees.record_payment(ctx.scope, ctx.e, cash(5_000))
    {:ok, view, _} = live(conn, ~p"/school/fees")

    assert has_element?(
             view,
             "#recent-payments a[href='/school/fees/receipts/#{p.id}/print']",
             p.number
           )
  end

  test "the bursar's menu shows Frais, Classes, Paramètres des frais; the censeur's shows Frais",
       ctx do
    bursar = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:bursar]})
    {:ok, view, _} = live(conn_for(ctx.scope, bursar.current_user), ~p"/school/fees")
    assert has_element?(view, "#nav-school-fees")
    assert has_element?(view, "#nav-school-classes")
    assert has_element?(view, "#nav-school-fee-settings")

    censeur = TeacherFixtures.member_scope_fixture(ctx.scope, %{roles: [:vice_principal]})
    {:ok, view, _} = live(conn_for(ctx.scope, censeur.current_user), ~p"/school/fees")
    assert has_element?(view, "#nav-school-fees")
  end

  test "without the frais module the menu item and the page are gone", %{conn: conn} = ctx do
    ws = ctx.scope.current_workspace
    operator = TeacherFixtures.admin_user_fixture()

    {:ok, _} =
      Organization.set_modules(%TeacherAssistant.Scope{current_user: operator}, ws, [:notes])

    assert {:error, {_, %{to: to}}} = live(conn, ~p"/school/fees")
    assert to =~ "/school"
  end
end
