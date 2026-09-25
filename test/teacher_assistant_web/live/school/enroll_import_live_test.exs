defmodule TeacherAssistantWeb.School.EnrollImportLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{name: "Lycée I"})

    scope = school_scope(user, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, cg2} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, cg2: cg2, actor: user, scope: scope}
  end

  test "paste → preview → confirm enrolls the students", %{conn: conn, cg: cg, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/import")

    view
    |> form("#import-form", %{"import" => %{"raw" => "Awa;f;M-1\nBi;m;"}})
    |> render_submit()

    assert render(view) =~ "Awa"
    view |> element("#import-confirm") |> render_click()
    assert length(Enrollment.list_roster(scope, cg)) == 2
  end

  test "matricule matching an existing student previews as réinscription", ctx do
    %{conn: conn, cg: cg, cg2: cg2, scope: scope} = ctx

    {:ok, %{enrollment: e}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    :ok = Enrollment.withdraw(scope, e)

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}/import")

    view
    |> form("#import-form", %{"import" => %{"raw" => "Awa;f;M-1"}})
    |> render_submit()

    assert render(view) =~ "éinscription"
    view |> element("#import-confirm") |> render_click()
    assert [%{enrollment: %{status: :reinscription}}] = Enrollment.list_roster(scope, cg2)
  end

  test "already-enrolled matricule is flagged as a conflict and skipped", ctx do
    %{conn: conn, cg: cg, cg2: cg2, scope: scope} = ctx
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Bi", sex: :m, matricule: "M-2"})

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}/import")

    view
    |> form("#import-form", %{"import" => %{"raw" => "Bi;m;M-2"}})
    |> render_submit()

    assert render(view) =~ "conflict" or render(view) =~ "conflit"
    view |> element("#import-confirm") |> render_click()
    assert [] = Enrollment.list_roster(scope, cg2)
  end

  test "non-admin cannot reach the import page", %{school: school, cg: cg, actor: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(other.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: _}}} = live(conn, ~p"/school/classes/#{cg.id}/import")
  end

  test "extra fields beyond the third are ignored", %{conn: conn, cg: cg, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/import")

    view
    |> form("#import-form", %{"import" => %{"raw" => "Awa;f;M-1;extra\nBi;m;"}})
    |> render_submit()

    assert render(view) =~ "Awa"
    view |> element("#import-confirm") |> render_click()
    assert length(Enrollment.list_roster(scope, cg)) == 2
  end
end
