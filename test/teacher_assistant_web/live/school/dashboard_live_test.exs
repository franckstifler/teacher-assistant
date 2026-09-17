defmodule TeacherAssistantWeb.School.DashboardLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  test "a member sees the school shell after selecting the school", %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée Central"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#school-dashboard")
    assert render(view) =~ "Lycée Central"
    assert has_element?(view, "#school-nav")
  end

  test "teacher pages redirect to /school while in a school scope without a teaching assignment",
       %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "École Guard"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/teacher/setup")
  end

  test "dashboard shows structure stats", %{conn: conn, actor: user} do
    alias TeacherAssistant.Academics
    alias TeacherAssistant.Academics.Enrollments

    {:ok, school} = Schools.create_school(user, %{name: "Lycée Stats"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})

    {:ok, _view, html} = live(conn, ~p"/school")
    assert html =~ "6e A" or html =~ "1"
  end

  test "dashboard without a year prompts to create one", %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "École SansAnnée"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")

    {:ok, view, html} = live(conn, ~p"/school")
    assert html =~ "année" or html =~ "year"
    assert has_element?(view, ~s(#school-dashboard a[href="/school/settings"]))
  end

  test "a plain teacher member sees the no-year gate without a settings link", %{
    conn: _conn,
    actor: head
  } do
    {:ok, school} = Schools.create_school(head, %{name: "École SansAnnéeVP"})
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, html} = live(conn, ~p"/school")
    assert html =~ "année" or html =~ "year"
    refute has_element?(view, ~s(#school-dashboard a[href="/school/settings"]))
  end

  describe "Mes classes section" do
    alias TeacherAssistant.Academics

    setup %{conn: conn, actor: head} do
      {:ok, school} = Schools.create_school(head, %{name: "Lycée Dash"})

      {:ok, year} =
        Academics.create_academic_year(school, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
      conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
      %{conn: conn, school: school, year: year, cg: cg, head: head}
    end

    test "shows Mes classes when the user is a form master", %{conn: conn, cg: cg, head: head} do
      {:ok, _} = Academics.set_form_master(cg, head.id)
      {:ok, _view, html} = live(conn, ~p"/school")
      assert html =~ "Mes classes"
      assert html =~ "6e A"
    end

    test "no Mes classes section when the user is not a form master", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/school")
      refute html =~ "Mes classes"
    end
  end

  describe "verification banner" do
    setup %{conn: conn, actor: head} do
      {:ok, school} = Schools.create_school(head, %{name: "Lycée Vérif"})
      conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
      %{conn: conn, school: school, head: head}
    end

    test "shows a pending-verification banner while unverified", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/school")
      assert has_element?(view, "#pending-verification")
      assert has_element?(view, "#setup-checklist")
    end

    test "hides the banner once verified", %{conn: conn, school: school, head: head} do
      {:ok, p} = Schools.fetch_school_profile(school)
      {:ok, _} = Schools.verify_school(p, head.id)
      {:ok, view, _html} = live(conn, ~p"/school")
      refute has_element?(view, "#pending-verification")
    end
  end
end
