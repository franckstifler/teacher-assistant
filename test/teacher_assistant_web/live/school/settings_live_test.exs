defmodule TeacherAssistantWeb.School.SettingsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "Ancien Nom"})
    # Setup-complete (active year + a class) so /school/settings isn't gated
    # to the wizard. Tests below that exercise year creation/activation add
    # their own additional years on top of this one.
    TeacherAssistant.TeacherFixtures.complete_school_setup!(school)
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, school: school}
  end

  test "head renames the school", %{conn: conn, school: school} do
    {:ok, view, _html} = live(conn, ~p"/school/settings")

    assert has_element?(view, "#school-settings")
    view |> form("#school-settings", %{"school" => %{"name" => "Nouveau Nom"}}) |> render_submit()

    assert TeacherAssistant.Organization.get_personal_workspace(school.id)
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

  test "creating a year from settings builds its calendar", %{conn: conn, school: school} do
    {:ok, view, _} = live(conn, ~p"/school/settings")

    view
    |> form("#year-form", %{
      "year" => %{"name" => "2030-2031", "start_date" => "2030-09-02", "end_date" => "2031-06-27"}
    })
    |> render_submit()

    year = Organization.list_academic_years(school) |> Enum.find(&(&1.name == "2030-2031"))
    assert length(Organization.list_sequences(year)) == 6
  end

  test "an active year without a calendar offers to generate it", %{conn: conn, school: school} do
    {:ok, bare} =
      Organization.create_academic_year(school, %{
        name: "2031-2032",
        start_date: ~D[2031-09-01],
        end_date: ~D[2032-06-26],
        active: true
      })

    # The active year needs a class or the setup gate sends us to the wizard.
    {:ok, _} = Enrollment.create_class_group(school, bare, %{label: "6e Z", level: "6ème"})

    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#generate-calendar-#{bare.id}")
    view |> element("#generate-calendar-#{bare.id}") |> render_click()
    assert length(Organization.list_sequences(bare)) == 6
    assert has_element?(view, "#year-calendar-#{bare.id}")
  end

  test "settings lists the active year's séquences", %{conn: conn, school: school} do
    year = Organization.current_academic_year(school)
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#year-calendar-#{year.id}")
    assert has_element?(view, "#year-calendar-#{year.id} li", "Séquence 6")
  end

  test "activating a year deactivates the previous one", %{conn: conn, school: school} do
    {:ok, y1} =
      Organization.create_academic_year(school, %{
        name: "2024-2025",
        start_date: ~D[2024-09-09],
        end_date: ~D[2025-07-31],
        active: true
      })

    # y1 is now the workspace's active year (it superseded the base
    # fixture's), so give it a class too or the setup-complete gate blocks
    # this request.
    {:ok, _cg} = Enrollment.create_class_group(school, y1, %{label: "6e A", level: "6ème"})

    {:ok, y2} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: false
      })

    {:ok, view, _} = live(conn, ~p"/school/settings")
    view |> element("#year-activate-#{y2.id}") |> render_click()

    assert Organization.current_academic_year(school).id == y2.id
    assert {:ok, %{active: false}} = Organization.get_academic_year(y1.id)
  end

  test "a plain teacher member cannot create years (forged event)", %{
    conn: _conn,
    school: school,
    actor: head
  } do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _html} = live(conn, ~p"/school/settings")
    refute has_element?(view, "#year-form")

    years_before = Organization.list_academic_years(school)

    render_hook(view, "create_year", %{
      "year" => %{"name" => "2025-2026", "start_date" => "2025-09-08", "end_date" => "2026-07-31"}
    })

    assert Organization.list_academic_years(school) == years_before
  end

  test "a vice_principal member sees the Settings nav link and can manage years", %{
    conn: _conn,
    school: school,
    actor: head
  } do
    vp = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{
        email: to_string(vp.email),
        roles: [:vice_principal]
      })

    {:ok, _} = Accounts.accept_invitation(inv.token, vp)

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

    assert Organization.list_academic_years(school) |> Enum.any?(&(&1.name == "2025-2026"))
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
    alias TeacherAssistant.Curriculum
    {:ok, view, _html} = live(conn, ~p"/school/settings")

    view
    |> form("#subject-form", subject: %{name: "Allemand", category: "language"})
    |> render_submit()

    subject = Curriculum.list_subjects(school) |> Enum.find(&(&1.name == "Allemand"))
    assert subject

    view
    |> form("#subject-edit-form-#{subject.id}",
      subject_edit: %{name: "Allemand", default_coefficient: "2.5", category: "language"}
    )
    |> render_submit()

    updated = Curriculum.list_subjects(school) |> Enum.find(&(&1.id == subject.id))
    assert Decimal.equal?(updated.default_coefficient, Decimal.new("2.5"))
  end

  test "admin deactivates and reactivates a subject", %{conn: conn, school: school} do
    alias TeacherAssistant.Curriculum
    {:ok, view, _html} = live(conn, ~p"/school/settings")

    view
    |> form("#subject-form", subject: %{name: "Allemand", category: "language"})
    |> render_submit()

    subject = Curriculum.list_subjects(school) |> Enum.find(&(&1.name == "Allemand"))
    assert subject

    view |> element("#subject-toggle-active-#{subject.id}") |> render_click()
    deactivated = Curriculum.list_subjects(school) |> Enum.find(&(&1.id == subject.id))
    assert deactivated.active? == false
    assert render(view) =~ "Réactiver"

    view |> element("#subject-toggle-active-#{subject.id}") |> render_click()
    reactivated = Curriculum.list_subjects(school) |> Enum.find(&(&1.id == subject.id))
    assert reactivated.active? == true
  end

  test "a plain teacher member cannot manage the subject catalog (forged events)", %{
    conn: conn,
    school: school,
    actor: head
  } do
    alias TeacherAssistant.Curriculum
    {:ok, view, _html} = live(conn, ~p"/school/settings")

    view
    |> form("#subject-form", subject: %{name: "Allemand", category: "language"})
    |> render_submit()

    subject = Curriculum.list_subjects(school) |> Enum.find(&(&1.name == "Allemand"))
    assert subject
    catalog_size_before = length(Curriculum.list_subjects(school))

    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, other)

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

    subjects = Curriculum.list_subjects(school)
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
    # Create first year directly with active: true
    {:ok, y1} =
      Organization.create_academic_year(school, %{
        name: "2024-2025",
        start_date: ~D[2024-09-09],
        end_date: ~D[2025-07-31],
        active: true
      })

    # y1 is now the workspace's active year (it superseded the base
    # fixture's), so give it a class too or the setup-complete gate blocks
    # this request.
    {:ok, _cg} = Enrollment.create_class_group(school, y1, %{label: "6e A", level: "6ème"})

    {:ok, view, _} = live(conn, ~p"/school/settings")

    # Submit form to create second year
    view
    |> form("#year-form", %{
      "year" => %{"name" => "2025-2026", "start_date" => "2025-09-08", "end_date" => "2026-07-31"}
    })
    |> render_submit()

    # First year must still be active
    assert Organization.current_academic_year(school).name == "2024-2025"

    # Second year must exist and be inactive
    years = Organization.list_academic_years(school)
    y2 = Enum.find(years, &(&1.name == "2025-2026"))
    assert y2 != nil
    assert y2.active == false
  end
end
