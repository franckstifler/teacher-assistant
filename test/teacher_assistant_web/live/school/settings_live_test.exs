defmodule TeacherAssistantWeb.School.SettingsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization
  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
        name: "Ancien Nom"
      })

    # Setup-complete (active year + a class) so /school/settings isn't gated
    # to the wizard. Tests below that exercise year creation/activation add
    # their own additional years on top of this one.
    scope = school_scope(user, school)
    TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    conn = post(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, school: school, scope: scope}
  end

  test "head renames the school", %{conn: conn, school: school, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/school/settings/profile")

    view
    |> form("#school-profile-form", %{"school" => %{"name" => "Nouveau Nom"}})
    |> render_submit()

    assert TeacherAssistant.Organization.get_workspace(school.id, scope: scope)
           |> elem(1)
           |> Map.get(:name) ==
             "Nouveau Nom"
  end

  test "an active year without a calendar offers to generate it", %{
    conn: conn,
    scope: scope
  } do
    {:ok, bare} =
      Organization.create_academic_year(scope, %{
        name: "2031-2032",
        start_date: ~D[2031-09-01],
        end_date: ~D[2032-06-26],
        active: true
      })

    # The active year needs a class or the setup gate sends us to the wizard.
    {:ok, _} = Enrollment.create_class_group(scope, bare, %{label: "6e Z", level: "6ème"})

    {:ok, view, _} = live(conn, ~p"/school/settings/year")
    assert has_element?(view, "#generate-calendar-#{bare.id}")
    view |> element("#generate-calendar-#{bare.id}") |> render_click()
    assert length(Organization.list_sequences(scope, bare)) == 6
    assert has_element?(view, "#year-calendar-#{bare.id}")
  end

  test "settings lists the active year's séquences", %{conn: conn, scope: scope} do
    year = TeacherAssistant.Organization.current_academic_year(scope)
    {:ok, view, _} = live(conn, ~p"/school/settings/year")
    assert has_element?(view, "#year-calendar-#{year.id}")
    assert has_element?(view, "#year-calendar-#{year.id}", "Séquence 6")
  end

  test "the calendar hint states the school's own grace days", %{conn: conn, scope: scope} do
    {:ok, _} = TeacherAssistant.Assessment.update_entry_grace_days(scope, "12")
    year = Organization.current_academic_year(scope)
    {:ok, view, _} = live(conn, ~p"/school/settings/year")
    assert has_element?(view, "#year-calendar-#{year.id}", "ferme 12 jours après la fin")
  end

  test "a vice_principal member sees the Settings nav link and the years", %{
    conn: _conn,
    school: school,
    actor: head
  } do
    vp = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(vp.email),
        roles: [:vice_principal]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: vp}, inv.token)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(vp)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, html} = live(conn, ~p"/school/sequences")
    assert html =~ "nav-school-settings"
    assert has_element?(view, "#nav-school-settings")

    {:ok, view, _html} = live(conn, ~p"/school/settings/year")
    assert has_element?(view, "#years-table")
  end

  test "years are listed with their status; none is created or activated here",
       %{conn: conn, scope: scope} do
    year = Organization.current_academic_year(scope)
    %{closed: closed, next: next} = TeacherAssistant.TeacherFixtures.close_year!(scope, year)

    {:ok, view, _} = live(conn, ~p"/school/settings/year")
    assert has_element?(view, "#year-row-#{next.id}", "Actif")
    assert has_element?(view, "#year-row-#{closed.id}", "Clôturée")
    refute has_element?(view, "#year-form")
    refute has_element?(view, "[id^=year-activate-]")
  end

  test "head can add and remove a subject", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/school/settings/subjects")

    view
    |> form("#subject-form", subject: %{name: "Allemand", bulletin_group: "g1_lettres"})
    |> render_submit()

    assert render(view) =~ "Allemand"

    view |> element("#subjects-table button", "Allemand") |> render_click()
    view |> element("[phx-click=\"delete_subject\"]", "Allemand") |> render_click()
    refute render(view) =~ "Allemand"
  end

  test "admin edits a subject's coefficient", %{conn: conn, scope: scope} do
    alias TeacherAssistant.Curriculum
    {:ok, view, _html} = live(conn, ~p"/school/settings/subjects")

    view
    |> form("#subject-form", subject: %{name: "Allemand", bulletin_group: "g1_lettres"})
    |> render_submit()

    subject = Curriculum.list_subjects(scope) |> Enum.find(&(&1.name == "Allemand"))
    assert subject

    view |> element("#subject-row-#{subject.id}") |> render_click()

    view
    |> form("#subject-edit-form-#{subject.id}",
      subject_edit: %{name: "Allemand", default_coefficient: "2.5", bulletin_group: "g1_lettres"}
    )
    |> render_submit()

    updated = Curriculum.list_subjects(scope) |> Enum.find(&(&1.id == subject.id))
    assert Decimal.equal?(updated.default_coefficient, Decimal.new("2.5"))
  end

  test "admin deactivates and reactivates a subject", %{conn: conn, scope: scope} do
    alias TeacherAssistant.Curriculum
    {:ok, view, _html} = live(conn, ~p"/school/settings/subjects")

    view
    |> form("#subject-form", subject: %{name: "Allemand", bulletin_group: "g1_lettres"})
    |> render_submit()

    subject = Curriculum.list_subjects(scope) |> Enum.find(&(&1.name == "Allemand"))
    assert subject

    view |> element("#subject-row-#{subject.id}") |> render_click()
    view |> element("#subject-toggle-active-#{subject.id}") |> render_click()
    deactivated = Curriculum.list_subjects(scope) |> Enum.find(&(&1.id == subject.id))
    assert deactivated.active? == false
    assert render(view) =~ "Réactiver"

    view |> element("#subject-toggle-active-#{subject.id}") |> render_click()
    reactivated = Curriculum.list_subjects(scope) |> Enum.find(&(&1.id == subject.id))
    assert reactivated.active? == true
  end

  test "a plain teacher member cannot manage the subject catalog (forged events)", %{
    conn: conn,
    school: school,
    actor: head,
    scope: scope
  } do
    alias TeacherAssistant.Curriculum
    {:ok, view, _html} = live(conn, ~p"/school/settings/subjects")

    view
    |> form("#subject-form", subject: %{name: "Allemand", bulletin_group: "g1_lettres"})
    |> render_submit()

    subject = Curriculum.list_subjects(scope) |> Enum.find(&(&1.name == "Allemand"))
    assert subject
    catalog_size_before = length(Curriculum.list_subjects(scope))

    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(other.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

    teacher_conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(other)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, tview, html} = live(teacher_conn, ~p"/school/settings")
    refute html =~ "id=\"matieres\""
    refute has_element?(tview, "#matieres")
    refute has_element?(tview, "#subject-form")

    render_hook(tview, "create_subject", %{
      "subject" => %{"name" => "Forged", "bulletin_group" => "g3_autres"}
    })

    render_hook(tview, "update_subject", %{
      "subject_id" => subject.id,
      "subject_edit" => %{
        "name" => "Hacked",
        "default_coefficient" => "9",
        "bulletin_group" => "g3_autres"
      }
    })

    render_hook(tview, "toggle_subject_active", %{"id" => subject.id})
    render_hook(tview, "delete_subject", %{"id" => subject.id})

    subjects = Curriculum.list_subjects(scope)
    assert length(subjects) == catalog_size_before
    refute Enum.any?(subjects, &(&1.name == "Forged"))

    reloaded = Enum.find(subjects, &(&1.id == subject.id))
    assert reloaded.name == "Allemand"
    assert reloaded.active? == true
    assert Decimal.equal?(reloaded.default_coefficient, Decimal.new(1))
  end

  test "head edits a séquence end and its grade-entry deadline", %{conn: conn, scope: scope} do
    year = Organization.current_academic_year(scope)
    [s1 | _] = Organization.list_sequences(scope, year)
    new_end = Date.add(s1.end_date, -2)
    {:ok, view, _} = live(conn, ~p"/school/settings/year")

    view
    |> form("#calendar-form", %{
      "calendar" => %{
        "sequences" => %{
          s1.id => %{
            "end_date" => Date.to_iso8601(new_end),
            "entry_deadline" => Date.to_iso8601(s1.end_date)
          }
        }
      }
    })
    |> render_submit()

    [u1 | _] = Organization.list_sequences(scope, year)
    assert u1.end_date == new_end
    assert u1.entry_deadline == s1.end_date
    assert render(view) =~ "Calendrier enregistré."
  end

  test "an overlapping séquence is flagged on its row and nothing is saved", %{
    conn: conn,
    scope: scope
  } do
    year = Organization.current_academic_year(scope)
    [s1, s2 | _] = Organization.list_sequences(scope, year)
    {:ok, view, _} = live(conn, ~p"/school/settings/year")

    view
    |> form("#calendar-form", %{
      "calendar" => %{"sequences" => %{s2.id => %{"start_date" => Date.to_iso8601(s1.end_date)}}}
    })
    |> render_submit()

    assert has_element?(
             view,
             "#sequence-#{s2.id}",
             "Commence avant la fin de la séquence précédente."
           )

    assert Enum.at(Organization.list_sequences(scope, year), 1).start_date == s2.start_date
  end

  test "deleting a subject a class uses explains why it stays", %{conn: conn, scope: scope} do
    year = Organization.current_academic_year(scope)
    [cg | _] = Enrollment.list_class_groups(scope, year)

    maths =
      Enum.find(TeacherAssistant.Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))

    {:ok, _} =
      TeacherAssistant.Curriculum.assign_teacher(scope, cg, scope.current_user, %{subject: maths})

    {:ok, view, _} = live(conn, ~p"/school/settings/subjects")
    view |> element("#subject-row-#{maths.id}") |> render_click()
    view |> element("#subject-delete-#{maths.id}") |> render_click()
    assert render(view) =~ "Matière utilisée par des classes : désactivez-la plutôt."
    assert Enum.any?(TeacherAssistant.Curriculum.list_subjects(scope), &(&1.id == maths.id))
  end

  test "a teacher sees the calendar read-only", %{school: school, scope: scope, actor: head} do
    teacher = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(teacher.email),
        roles: [:teacher]
      })

    {:ok, _} =
      Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: teacher}, inv.token)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(teacher)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    year = Organization.current_academic_year(scope)
    [s1 | _] = Organization.list_sequences(scope, year)
    {:ok, view, _} = live(conn, ~p"/school/settings/year")

    assert has_element?(view, "#year-calendar-#{year.id}", "Séquence 1")
    assert has_element?(view, "input[name='calendar[sequences][#{s1.id}][end_date]'][disabled]")
    refute has_element?(view, "#calendar-form button[type=submit]")
    refute has_element?(view, "#year-form")
  end

  test "settings hub links to the rooms page", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/school/settings")
    assert has_element?(view, "#rooms-link")
  end

  test "a subject's default room is saved from the subjects page", %{conn: conn, scope: scope} do
    alias TeacherAssistant.{Curriculum, Organization}
    {:ok, info} = Organization.create_room(scope, %{name: "Salle info", kind: :computer_room})
    [subject | _] = Curriculum.list_subjects(scope)

    {:ok, view, _} = live(conn, ~p"/school/settings/subjects")
    view |> element("#subject-row-#{subject.id}") |> render_click()
    assert has_element?(view, "#subject-edit-form-#{subject.id} option", "Salle info")

    view
    |> form("#subject-edit-form-#{subject.id}", subject_edit: %{default_room_id: info.id})
    |> render_submit()

    assert Enum.find(Curriculum.list_subjects(scope), &(&1.id == subject.id)).default_room_id ==
             info.id
  end

  test "saving a subject keeps a default room that was deactivated", %{conn: conn, scope: scope} do
    alias TeacherAssistant.{Curriculum, Organization}
    {:ok, info} = Organization.create_room(scope, %{name: "Salle info", kind: :computer_room})
    [subject | _] = Curriculum.list_subjects(scope)
    {:ok, subject} = Curriculum.update_subject(scope, subject, %{default_room_id: info.id})
    {:ok, _} = Organization.update_room(scope, info, %{active?: false})

    {:ok, view, _} = live(conn, ~p"/school/settings/subjects")
    view |> element("#subject-row-#{subject.id}") |> render_click()

    view
    |> form("#subject-edit-form-#{subject.id}", subject_edit: %{name: subject.name <> " 2"})
    |> render_submit()

    assert Enum.find(Curriculum.list_subjects(scope), &(&1.id == subject.id)).default_room_id ==
             info.id
  end
end
