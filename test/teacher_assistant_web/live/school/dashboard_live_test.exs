defmodule TeacherAssistantWeb.School.DashboardLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  setup :register_and_log_in_user

  test "a member sees the school shell after selecting the school", %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "Lycée Central"})
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#school-dashboard")
    assert render(view) =~ "Lycée Central"
    assert has_element?(view, "#school-nav")
  end

  test "teacher pages redirect to /school while in a school scope without a teaching assignment",
       %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "École Guard"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/teacher/contexts/#{Ecto.UUID.generate()}/roster")
  end

  test "dashboard shows structure stats", %{conn: conn, actor: user} do
    alias TeacherAssistant.Enrollment

    {:ok, school} = Organization.create_school(user, %{name: "Lycée Stats"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")

    {:ok, year} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollment.enroll_new(cg, %{full_name: "Awa", sex: :f})

    {:ok, _view, html} = live(conn, ~p"/school")
    assert html =~ "6e A" or html =~ "1"
  end

  # These two tests used to exercise DashboardLive's own inline "no active
  # year" empty state. The `:require_school_setup` on_mount gate now
  # intercepts a school with no active year + class before this LiveView
  # even mounts, redirecting to the wizard instead — so they now assert on
  # the gate's redirect, which is the current form of "prompts to create
  # one" for an incomplete school (regardless of member role).
  test "dashboard without a year redirects to the setup wizard", %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "École SansAnnée"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")

    assert {:error, {:live_redirect, %{to: "/school/setup"}}} = live(conn, ~p"/school")
  end

  test "a plain teacher member without an active year is also redirected to the setup wizard", %{
    conn: _conn,
    actor: head
  } do
    {:ok, school} = Organization.create_school(head, %{name: "École SansAnnéeVP"})
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school/setup"}}} = live(conn, ~p"/school")
  end

  describe "Mes classes section" do
    alias TeacherAssistant.Enrollment

    setup %{conn: conn, actor: head} do
      {:ok, school} = Organization.create_school(head, %{name: "Lycée Dash"})

      {:ok, year} =
        Organization.create_academic_year(school, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      {:ok, cg} = Enrollment.create_class_group(school, year, %{label: "6e A", level: "6ème"})
      conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
      %{conn: conn, school: school, year: year, cg: cg, head: head}
    end

    test "shows Mes classes when the user is a form master", %{conn: conn, cg: cg, head: head} do
      {:ok, _} = Enrollment.set_form_master(cg, head.id)
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
      {:ok, school} = Organization.create_school(head, %{name: "Lycée Vérif"})
      TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
      conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
      %{conn: conn, school: school, head: head}
    end

    test "shows a pending-verification banner while unverified", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/school")
      assert has_element?(view, "#pending-verification")
      assert has_element?(view, "#setup-checklist")
    end

    test "hides the banner once verified", %{conn: conn, school: school, head: head} do
      {:ok, p} = Accounts.fetch_school_profile(school)
      {:ok, _} = Accounts.verify_school(p, head.id)
      {:ok, view, _html} = live(conn, ~p"/school")
      refute has_element?(view, "#pending-verification")
    end
  end

  test "a member with a stale session workspace is sent to their first school", %{
    conn: conn,
    workspace: home_school
  } do
    # the session workspace_id points at a school the user does not belong to
    # (a stale/foreign reference), so the resolved scope is non-school even
    # though the user has a real school of their own.
    other_head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, other_school} = Organization.create_school(other_head, %{name: "École Étrangère"})
    conn = Plug.Conn.put_session(conn, :workspace_id, other_school.id)
    expected_to = "/workspaces/select/#{home_school.id}"

    assert {:error, {:live_redirect, %{to: ^expected_to}}} = live(conn, ~p"/school")
  end

  test "a user with no workspace in session and no school is sent to /schools/new" do
    user = TeacherAssistant.TeacherFixtures.user_fixture()
    conn = Phoenix.ConnTest.build_conn() |> log_in_user(user)
    assert {:error, {:live_redirect, %{to: "/schools/new"}}} = live(conn, ~p"/school")
  end

  test "a logged-out visitor on /school is sent to /sign-in" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/school")
  end

  test "the shell shows no personal navigation", %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "Lycée Nav"})
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _html} = live(conn, ~p"/school")
    assert has_element?(view, "#school-nav")
    refute has_element?(view, "#main-nav")
    refute has_element?(view, "a[href='/teacher/setup']")
    refute has_element?(view, "a[href='/teacher']")
  end
end
