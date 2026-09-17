defmodule TeacherAssistantWeb.School.SettingsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Ancien Nom"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, school: school}
  end

  test "head renames the school", %{conn: conn, school: school} do
    {:ok, view, _html} = live(conn, ~p"/school/settings")

    assert has_element?(view, "#school-settings")
    view |> form("#school-settings", %{"school" => %{"name" => "Nouveau Nom"}}) |> render_submit()

    assert TeacherAssistant.Academics.get_personal_workspace(school.id)
           |> elem(1)
           |> Map.get(:name) ==
             "Nouveau Nom"
  end

  test "head creates and activates an academic year", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")

    view
    |> form("#year-form", %{
      "year" => %{"name" => "2025-2026", "start_date" => "2025-09-08", "end_date" => "2026-07-31"}
    })
    |> render_submit()

    assert render(view) =~ "2025-2026"
  end

  test "activating a year deactivates the previous one", %{conn: conn, school: school} do
    alias TeacherAssistant.Academics

    {:ok, y1} =
      Academics.create_academic_year(school, %{
        name: "2024-2025",
        start_date: ~D[2024-09-09],
        end_date: ~D[2025-07-31],
        active: true
      })

    {:ok, y2} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: false
      })

    {:ok, view, _} = live(conn, ~p"/school/settings")
    view |> element("#year-activate-#{y2.id}") |> render_click()

    assert Academics.current_academic_year(school).id == y2.id
    assert {:ok, %{active: false}} = Academics.get_academic_year(y1.id)
  end

  test "a plain teacher member cannot create years (forged event)", %{
    conn: _conn,
    school: school,
    actor: head
  } do
    alias TeacherAssistant.Academics

    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _html} = live(conn, ~p"/school/settings")
    refute has_element?(view, "#year-form")

    render_hook(view, "create_year", %{
      "year" => %{"name" => "2025-2026", "start_date" => "2025-09-08", "end_date" => "2026-07-31"}
    })

    assert Academics.list_academic_years(school) == []
  end

  test "a vice_principal member sees the Settings nav link and can manage years", %{
    conn: _conn,
    school: school,
    actor: head
  } do
    alias TeacherAssistant.Academics

    vp = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{
        email: to_string(vp.email),
        roles: [:vice_principal]
      })

    {:ok, _} = Schools.accept_invitation(inv.token, vp)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, vp.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, html} = live(conn, ~p"/school")
    assert html =~ "nav-school-settings"
    assert has_element?(view, "#nav-school-settings")

    {:ok, view, _html} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#year-form")

    view
    |> form("#year-form", %{
      "year" => %{"name" => "2025-2026", "start_date" => "2025-09-08", "end_date" => "2026-07-31"}
    })
    |> render_submit()

    assert Academics.list_academic_years(school) |> Enum.any?(&(&1.name == "2025-2026"))
  end

  test "head can add and remove a subject", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/school/settings")

    view
    |> form("#subject-form", subject: %{name: "Allemand", category: "language"})
    |> render_submit()

    assert render(view) =~ "Allemand"

    view |> element("[phx-click=\"delete_subject\"]", "Allemand") |> render_click()
    refute render(view) =~ "Allemand"
  end

  test "admin edits a subject's coefficient", %{conn: conn, school: school} do
    alias TeacherAssistant.Academics.Subjects

    {:ok, view, _html} = live(conn, ~p"/school/settings")

    view
    |> form("#subject-form", subject: %{name: "Allemand", category: "language"})
    |> render_submit()

    subject = Subjects.list(school) |> Enum.find(&(&1.name == "Allemand"))
    assert subject

    view
    |> form("#subject-edit-form-#{subject.id}",
      subject_edit: %{name: "Allemand", default_coefficient: "2.5", category: "language"}
    )
    |> render_submit()

    updated = Subjects.list(school) |> Enum.find(&(&1.id == subject.id))
    assert Decimal.equal?(updated.default_coefficient, Decimal.new("2.5"))
  end

  test "admin deactivates and reactivates a subject", %{conn: conn, school: school} do
    alias TeacherAssistant.Academics.Subjects

    {:ok, view, _html} = live(conn, ~p"/school/settings")

    view
    |> form("#subject-form", subject: %{name: "Allemand", category: "language"})
    |> render_submit()

    subject = Subjects.list(school) |> Enum.find(&(&1.name == "Allemand"))
    assert subject

    view |> element("#subject-toggle-active-#{subject.id}") |> render_click()
    deactivated = Subjects.list(school) |> Enum.find(&(&1.id == subject.id))
    assert deactivated.active? == false
    assert render(view) =~ "Réactiver"

    view |> element("#subject-toggle-active-#{subject.id}") |> render_click()
    reactivated = Subjects.list(school) |> Enum.find(&(&1.id == subject.id))
    assert reactivated.active? == true
  end

  test "a plain teacher member cannot manage the subject catalog (forged events)", %{
    conn: conn,
    school: school,
    actor: head
  } do
    alias TeacherAssistant.Academics.Subjects

    {:ok, view, _html} = live(conn, ~p"/school/settings")

    view
    |> form("#subject-form", subject: %{name: "Allemand", category: "language"})
    |> render_submit()

    subject = Subjects.list(school) |> Enum.find(&(&1.name == "Allemand"))
    assert subject
    catalog_size_before = length(Subjects.list(school))

    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    teacher_conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, tview, html} = live(teacher_conn, ~p"/school/settings")
    refute html =~ "id=\"matieres\""
    refute has_element?(tview, "#matieres")
    refute has_element?(tview, "#subject-form")

    render_hook(tview, "create_subject", %{
      "subject" => %{"name" => "Forged", "category" => "general"}
    })

    render_hook(tview, "update_subject", %{
      "subject_id" => subject.id,
      "subject_edit" => %{
        "name" => "Hacked",
        "default_coefficient" => "9",
        "category" => "general"
      }
    })

    render_hook(tview, "toggle_subject_active", %{"id" => subject.id})
    render_hook(tview, "delete_subject", %{"id" => subject.id})

    subjects = Subjects.list(school)
    assert length(subjects) == catalog_size_before
    refute Enum.any?(subjects, &(&1.name == "Forged"))

    reloaded = Enum.find(subjects, &(&1.id == subject.id))
    assert reloaded.name == "Allemand"
    assert reloaded.active? == true
    assert Decimal.equal?(reloaded.default_coefficient, Decimal.new(1))
  end

  test "additional academic years created via form are inactive; only first is active", %{
    conn: conn,
    school: school
  } do
    alias TeacherAssistant.Academics

    # Create first year directly with active: true
    {:ok, _y1} =
      Academics.create_academic_year(school, %{
        name: "2024-2025",
        start_date: ~D[2024-09-09],
        end_date: ~D[2025-07-31],
        active: true
      })

    {:ok, view, _} = live(conn, ~p"/school/settings")

    # Submit form to create second year
    view
    |> form("#year-form", %{
      "year" => %{"name" => "2025-2026", "start_date" => "2025-09-08", "end_date" => "2026-07-31"}
    })
    |> render_submit()

    # First year must still be active
    assert Academics.current_academic_year(school).name == "2024-2025"

    # Second year must exist and be inactive
    years = Academics.list_academic_years(school)
    y2 = Enum.find(years, &(&1.name == "2025-2026"))
    assert y2 != nil
    assert y2.active == false
  end
end
