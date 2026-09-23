defmodule TeacherAssistantWeb.School.ClassesLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "Lycée C"})

    {:ok, year} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    # At least one class so the :require_school_setup gate lets these tests
    # (which mostly exercise class management once setup is already done)
    # reach /school/classes.
    {:ok, _seed_cg} =
      Enrollment.create_class_group(school, year, %{label: "Seed", level: "6ème"})

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, user: user}
  end

  test "lists classes with effectif", %{conn: conn, school: school, year: year} do
    {:ok, cg} = Enrollment.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollment.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, _view, html} = live(conn, ~p"/school/classes")
    assert html =~ "6e A"
    assert html =~ "1"
  end

  test "head can create a class", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/classes")

    view
    |> form("#class-form", %{
      "class_group" => %{"label" => "2nde C", "level" => "2nde", "serie" => "C"}
    })
    |> render_submit()

    assert render(view) =~ "2nde C"
  end

  test "série field offers template suggestions", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/school/classes")
    # datalist of séries from the lycée template
    assert html =~ "list=\"serie-options\""
    assert html =~ "C"
    assert html =~ "D"
  end

  test "delete is blocked when the class has enrollments", ctx do
    %{conn: conn, school: school, year: year} = ctx
    {:ok, cg} = Enrollment.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollment.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes")
    view |> element("#class-delete-#{cg.id}") |> render_click()
    assert render(view) =~ "6e A"
  end

  test "a plain teacher member sees no admin controls and forged events are rejected", ctx do
    %{conn: _conn, school: school, year: year, user: head} = ctx
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _html} = live(conn, ~p"/school/classes")
    refute has_element?(view, "#class-form")

    before_labels = school |> Enrollment.list_class_groups(year) |> Enum.map(& &1.label)

    render_hook(view, "create_class", %{"class_group" => %{"label" => "X", "level" => "6ème"}})

    after_labels = school |> Enrollment.list_class_groups(year) |> Enum.map(& &1.label)
    assert after_labels == before_labels
    refute "X" in after_labels
  end

  # These two tests used to exercise ClassesLive's own inline "no active
  # year" empty state. The `:require_school_setup` on_mount gate now
  # intercepts a school with no active year + class before this LiveView
  # even mounts, redirecting to the wizard instead (regardless of member
  # role) — so they now assert on that redirect.
  test "no active year redirects to the setup wizard", %{conn: conn, actor: user} do
    {:ok, school2} = Organization.create_school(user, %{name: "Lycée SansAnnée"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school2.id)
    assert {:error, {:live_redirect, %{to: "/school/setup"}}} = live(conn, ~p"/school/classes")
  end

  test "a plain teacher member without an active year is also redirected to the setup wizard", %{
    conn: _conn,
    actor: head
  } do
    {:ok, school2} = Organization.create_school(head, %{name: "Lycée SansAnnéeVP"})
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school2, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school2.id)

    assert {:error, {:live_redirect, %{to: "/school/setup"}}} = live(conn, ~p"/school/classes")
  end
end
