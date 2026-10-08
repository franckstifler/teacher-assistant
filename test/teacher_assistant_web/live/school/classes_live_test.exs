defmodule TeacherAssistantWeb.School.ClassesLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{name: "Lycée C"})

    scope = school_scope(user, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    # At least one class so the :require_school_setup gate lets these tests
    # (which mostly exercise class management once setup is already done)
    # reach /school/classes.
    {:ok, _seed_cg} =
      Enrollment.create_class_group(scope, year, %{label: "Seed", level: "6ème"})

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, user: user, scope: scope}
  end

  test "lists classes with effectif", %{conn: conn, scope: scope, year: year} do
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _view, html} = live(conn, ~p"/school/classes")
    assert html =~ "6e A"
    assert html =~ "1"
  end

  test "head creates a class from the drawer and lands on it", %{
    conn: conn,
    scope: scope,
    year: year
  } do
    {:ok, view, _} = live(conn, ~p"/school/classes")
    view |> element("#new-class-button") |> render_click()

    view |> form("#class-form", %{"nc" => %{"level" => "2nde"}}) |> render_change()
    # séries are offered for a streamed level
    assert has_element?(view, "#nc-serie-c")
    assert has_element?(view, "#nc-serie-d")

    view
    |> form("#class-form", %{"nc" => %{"level" => "2nde", "serie" => "C"}})
    |> render_change()

    assert has_element?(view, "#nc-preview", "2nde C A")

    {:error, {:live_redirect, %{to: to}}} =
      view
      |> form("#class-form", %{
        "nc" => %{"level" => "2nde", "serie" => "C", "suffix" => "A"},
        "class_group" => %{"max_size" => "45"}
      })
      |> render_submit()

    cg = Enum.find(Enrollment.list_class_groups(scope, year), &(&1.label == "2nde C A"))
    assert to == "/school/classes/#{cg.id}"
    assert cg.serie == "C"
    assert cg.max_size == 45
  end

  test "a label already used this year cannot be created", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/classes")
    view |> element("#new-class-button") |> render_click()

    view |> form("#class-form", %{"nc" => %{"level" => "__other__"}}) |> render_change()

    view
    |> form("#class-form", %{"nc" => %{"level" => "__other__", "other_level" => "Seed"}})
    |> render_change()

    # a new level proposes a free suffix; clearing it gives the bare, taken label

    view
    |> form("#class-form", %{
      "nc" => %{"level" => "__other__", "other_level" => "Seed", "suffix" => ""}
    })
    |> render_change()

    assert has_element?(view, "#nc-duplicate")
    assert has_element?(view, "#create-class[disabled]")
  end

  test "a class spelt differently at the same level still takes its suffix", ctx do
    %{conn: conn, scope: scope, year: year} = ctx
    {:ok, _} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})

    {:ok, view, _} = live(conn, ~p"/school/classes")
    view |> element("#new-class-button") |> render_click()
    view |> form("#class-form", %{"nc" => %{"level" => "6ème"}}) |> render_change()

    assert has_element?(view, "#nc-suffix[value='B']")
    assert render(view) =~ "Déjà : 6e A"

    view
    |> form("#class-form", %{"nc" => %{"level" => "6ème", "suffix" => "A"}})
    |> render_change()

    assert has_element?(view, "#nc-duplicate")
  end

  test "cards are grouped by cycle and filtered by cycle and text", ctx do
    %{conn: conn, scope: scope, year: year} = ctx
    {:ok, a} = Enrollment.create_class_group(scope, year, %{label: "Tle D", level: "Terminale"})

    {:ok, f} =
      Enrollment.create_class_group(scope, year, %{
        label: "Form 1",
        level: "Form 1",
        subsystem: :anglophone
      })

    {:ok, view, _} = live(conn, ~p"/school/classes")
    assert has_element?(view, "#cycle-group-first")
    assert has_element?(view, "#cycle-group-second #class-card-#{a.id}")
    assert has_element?(view, "#cycle-group-anglophone #class-card-#{f.id}")

    view |> element("#cycle-second") |> render_click()
    refute has_element?(view, "#cycle-group-first")
    assert has_element?(view, "#class-card-#{a.id}")

    view |> element("#cycle-all") |> render_click()
    view |> form("#class-filter", %{"q" => "form"}) |> render_change()
    assert has_element?(view, "#class-card-#{f.id}")
    refute has_element?(view, "#class-card-#{a.id}")

    view |> form("#class-filter", %{"q" => "zzz"}) |> render_change()
    assert has_element?(view, "#no-class-match")
  end

  test "a plain teacher member sees no admin controls and forged events are rejected", ctx do
    %{conn: _conn, school: school, year: year, user: head, scope: scope} = ctx
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

    {:ok, view, _html} = live(conn, ~p"/school/classes")
    refute has_element?(view, "#new-class-button")
    render_hook(view, "open_drawer", %{})
    refute has_element?(view, "#class-form")

    before_labels = Enrollment.list_class_groups(scope, year) |> Enum.map(& &1.label)

    render_hook(view, "create_class", %{"nc" => %{"level" => "6ème", "suffix" => "X"}})

    after_labels = Enrollment.list_class_groups(scope, year) |> Enum.map(& &1.label)
    assert after_labels == before_labels
    refute "6ème X" in after_labels
  end

  # These two tests used to exercise ClassesLive's own inline "no active
  # year" empty state. The `:require_school_setup` on_mount gate now
  # intercepts a school with no active year + class before this LiveView
  # even mounts, redirecting to the wizard instead (regardless of member
  # role) — so they now assert on that redirect.
  test "no active year redirects to the setup wizard", %{conn: conn, actor: user} do
    {:ok, school2} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Lycée SansAnnée"
      })

    conn = Plug.Conn.put_session(conn, :workspace_id, school2.id)
    assert {:error, {:live_redirect, %{to: "/school/setup"}}} = live(conn, ~p"/school/classes")
  end

  test "a plain teacher member without an active year is also redirected to the setup wizard", %{
    conn: _conn,
    actor: head
  } do
    {:ok, school2} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée SansAnnéeVP"
      })

    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school2), %{
        email: to_string(other.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school2.id)

    assert {:error, {:live_redirect, %{to: "/school/setup"}}} = live(conn, ~p"/school/classes")
  end
end
