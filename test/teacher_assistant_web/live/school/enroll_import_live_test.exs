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

    assert view |> element("#import-preview-rows") |> render() =~
             "Déjà inscrit cette année (6e A)"

    assert view |> element("#import-chip-conflict") |> render() =~ "1 conflit"
    assert has_element?(view, "#import-confirm[disabled]")
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

  test "tab-separated lines and extra fields are accepted", %{conn: conn, cg: cg, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/import")

    view
    |> form("#import-form", %{"import" => %{"raw" => "Awa\tf\tM-1\t\t\t\textra\nBi;m;"}})
    |> render_submit()

    assert render(view) =~ "Awa"
    view |> element("#import-confirm") |> render_click()
    assert length(Enrollment.list_roster(scope, cg)) == 2
  end

  test "imports birth dates and links a sibling's parent by phone; an invalid number is reported",
       %{conn: conn, scope: scope, cg: cg} do
    {:ok, paul} = Enrollment.add_student(scope, cg, %{full_name: "Paul Nkolo", sex: :m})

    {:ok, jean} =
      Enrollment.add_guardian(scope, paul, %{
        full_name: "Jean Nkolo",
        relationship: :pere,
        phone: "677123456"
      })

    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/import")

    raw = "Awa Nkolo;f;M-9;02/04/2013;+237 677 12 34 56\nZoé;f;;31/02/2010;12\nMoko;;;;"

    view |> form("#import-form", %{"import" => %{"raw" => raw}}) |> render_submit()

    preview = view |> element("#import-preview-rows") |> render()
    assert preview =~ "F · 02/04/2013"
    assert preview =~ "Parent existant lié : Jean Nkolo"
    assert preview =~ "Numéro « 12 » invalide — parent ignoré"
    assert preview =~ "Sexe manquant ou inconnu (M ou F)"
    assert view |> element("#import-chip-error") |> render() =~ "1 erreur"

    assert view |> element("#import-chip-invalid-phone") |> render() =~
             "1 numéro de parent invalide"

    assert view |> element("#import-confirm") |> render() =~ "Confirmer l&#39;import de 2 élèves"
    assert view |> element("#import-after") |> render() =~ "Après import : 3 élèves."

    view |> element("#import-confirm") |> render_click()

    awa = Enrollment.list_students(scope, cg) |> Enum.find(&(&1.full_name == "Awa Nkolo"))
    assert awa.birth_date == ~D[2013-04-02]

    assert [%{guardian: %{id: id}, primary_contact: true}] =
             Enrollment.list_guardian_links(scope, awa)

    assert id == jean.id

    zoe = Enrollment.list_students(scope, cg) |> Enum.find(&(&1.full_name == "Zoé"))
    assert zoe.birth_date == nil
    assert Enrollment.list_guardian_links(scope, zoe) == []

    done = view |> element("#import-done") |> render()
    assert done =~ "2 inscriptions, 0 réinscription."
    assert done =~ "Moko — sexe manquant ou inconnu."
    assert done =~ "Parent non enregistré pour Zoé (numéro « 12 » invalide)."
  end

  test "a matricule held by another student is a conflict, not a re-enrolment", ctx do
    %{conn: conn, cg: cg, cg2: cg2, scope: scope} = ctx

    {:ok, %{enrollment: e}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Ebogo Sandrine", sex: :f, matricule: "M-7"})

    :ok = Enrollment.withdraw(scope, e)

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}/import")

    view
    |> form("#import-form", %{"import" => %{"raw" => "Mvogo Diane;f;M-7"}})
    |> render_submit()

    assert view |> element("#import-preview-rows") |> render() =~
             "Matricule déjà utilisé (Ebogo Sandrine)"

    assert view |> element("#import-confirm[disabled]") |> has_element?()
  end

  test "« Importer une autre liste » starts over", %{conn: conn, cg: cg} do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/import")
    view |> form("#import-form", %{"import" => %{"raw" => "Awa;f"}}) |> render_submit()
    view |> element("#import-confirm") |> render_click()
    view |> element("#import-restart") |> render_click()
    assert has_element?(view, "#import-form")
    refute view |> element("#import-raw") |> render() =~ "Awa"
  end
end
