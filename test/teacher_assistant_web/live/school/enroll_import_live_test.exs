defmodule TeacherAssistantWeb.School.EnrollImportLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Enrollments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée I"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, cg2} = Academics.create_class_group(school, year, %{label: "6e B", level: "6ème"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, cg2: cg2, actor: user}
  end

  test "paste → preview → confirm enrolls the students", %{conn: conn, cg: cg} do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/import")

    view
    |> form("#import-form", %{"import" => %{"raw" => "Awa;f;M-1\nBi;m;"}})
    |> render_submit()

    assert render(view) =~ "Awa"
    view |> element("#import-confirm") |> render_click()
    assert length(Academics.list_roster(cg)) == 2
  end

  test "matricule matching an existing student previews as réinscription", ctx do
    %{conn: conn, cg: cg, cg2: cg2} = ctx

    {:ok, %{enrollment: e}} =
      Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})

    :ok = Enrollments.withdraw(e)

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}/import")

    view
    |> form("#import-form", %{"import" => %{"raw" => "Awa;f;M-1"}})
    |> render_submit()

    assert render(view) =~ "éinscription"
    view |> element("#import-confirm") |> render_click()
    assert [%{enrollment: %{status: :reinscription}}] = Academics.list_roster(cg2)
  end

  test "already-enrolled matricule is flagged as a conflict and skipped", ctx do
    %{conn: conn, cg: cg, cg2: cg2} = ctx
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Bi", sex: :m, matricule: "M-2"})

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}/import")

    view
    |> form("#import-form", %{"import" => %{"raw" => "Bi;m;M-2"}})
    |> render_submit()

    assert render(view) =~ "conflict" or render(view) =~ "conflit"
    view |> element("#import-confirm") |> render_click()
    assert [] = Academics.list_roster(cg2)
  end

  test "non-admin cannot reach the import page", %{school: school, cg: cg, actor: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: _}}} = live(conn, ~p"/school/classes/#{cg.id}/import")
  end
end
