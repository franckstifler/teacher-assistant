defmodule TeacherAssistantWeb.School.DisciplineLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Discipline
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée D"})

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})

    {:ok, _student} = Enrollment.add_student(scope, cg, %{full_name: "Awa Nkolo", sex: :f})
    [%{enrollment: enrollment}] = Enrollment.list_roster(scope, cg)

    sequence = Organization.current_sequence(scope, year, ~D[2025-09-08])

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      school: school,
      year: year,
      cg: cg,
      head: head,
      scope: scope,
      enrollment: enrollment,
      sequence: sequence
    }
  end

  defp conn_for(school, user) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  test "a conduct manager adds a sanction, sees it in the log, and deletes it", %{
    school: school,
    cg: cg,
    head: head,
    scope: scope,
    enrollment: enrollment
  } do
    dm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(dm.email),
        roles: [:discipline_master]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: dm}, inv.token)

    conn = conn_for(school, dm)

    {:ok, view, html} = live(conn, ~p"/school/classes/#{cg.id}/discipline")

    assert html =~ "Awa Nkolo"
    assert has_element?(view, "#discipline-add-form")

    view
    |> form("#discipline-add-form", %{
      "enrollment_id" => enrollment.id,
      "type" => "avertissement",
      "date" => "2025-09-10",
      "reason" => "Bavardage"
    })
    |> render_submit()

    sanctions =
      Discipline.list_sanctions(
        scope,
        cg,
        {:sequence,
         Organization.current_sequence(
           scope,
           Organization.current_academic_year(scope),
           ~D[2025-09-10]
         )}
      )

    assert [sanction] = sanctions
    assert sanction.type == :avertissement
    assert sanction.reason == "Bavardage"

    view
    |> element("#delete-sanction-#{sanction.id}")
    |> render_click()

    assert Discipline.list_sanctions(
             scope,
             cg,
             {:sequence,
              Organization.current_sequence(
                scope,
                Organization.current_academic_year(scope),
                ~D[2025-09-10]
              )}
           ) == []
  end

  test "an exclusion temporaire sanction stores its duration", %{
    school: school,
    cg: cg,
    head: head,
    scope: scope,
    enrollment: enrollment
  } do
    dm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(dm.email),
        roles: [:discipline_master]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: dm}, inv.token)

    conn = conn_for(school, dm)

    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/discipline")

    # Only the chosen type's duration is asked for.
    refute has_element?(view, "#discipline-add-form input[name='duration_hours']")
    view |> element("#discipline-add-form") |> render_change(%{"type" => "exclusion_temporaire"})
    refute has_element?(view, "#discipline-add-form input[name='duration_hours']")

    view
    |> form("#discipline-add-form", %{
      "enrollment_id" => enrollment.id,
      "type" => "exclusion_temporaire",
      "date" => "2025-09-10",
      "duration_days" => "3",
      "reason" => "Bagarre"
    })
    |> render_submit()

    [sanction] =
      Discipline.list_sanctions(
        scope,
        cg,
        {:sequence,
         Organization.current_sequence(
           scope,
           Organization.current_academic_year(scope),
           ~D[2025-09-10]
         )}
      )

    assert sanction.type == :exclusion_temporaire
    assert sanction.duration_days == 3
  end

  test "a conduct manager enters conduct marks on the Conduite page, linked from here", %{
    school: school,
    cg: cg,
    head: head,
    enrollment: enrollment,
    sequence: sequence
  } do
    dm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(dm.email),
        roles: [:discipline_master]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: dm}, inv.token)

    conn = conn_for(school, dm)

    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/discipline")

    # One place to enter conduct: the « Conduite » page, on this class and séquence.
    assert has_element?(
             view,
             ~s|#conduct-link[href="/school/conduct?class=#{cg.id}&seq=#{sequence.id}"]|
           )

    refute has_element?(view, "#note-form-#{enrollment.id}")
  end

  test "the period selector reloads the sanctions log", %{
    conn: _conn,
    school: school,
    cg: cg,
    year: year,
    head: head,
    scope: scope,
    enrollment: enrollment
  } do
    {:ok, _sanction} =
      Discipline.add_sanction(
        scope,
        enrollment,
        %{type: :blame, date: ~D[2025-09-10], reason: "Retard"}
      )

    sequence = Organization.current_sequence(scope, year, ~D[2025-09-10])

    other_sequences =
      Organization.list_sequences(scope, year) |> Enum.reject(&(&1.id == sequence.id))

    conn = conn_for(school, head)

    {:ok, view, html} = live(conn, ~p"/school/classes/#{cg.id}/discipline")
    assert html =~ "Retard"

    if other_sequences != [] do
      other = hd(other_sequences)

      html =
        view
        |> form("#discipline-period-form", %{"period" => "seq:#{other.id}"})
        |> render_change()

      refute html =~ "Retard"
    end
  end

  test "a form master sees a read-only page and forged events are rejected", %{
    school: school,
    cg: cg,
    head: head,
    scope: scope,
    enrollment: enrollment
  } do
    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(fm.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: fm}, inv.token)
    {:ok, _} = Enrollment.set_form_master(scope, cg, fm.id)

    conn = conn_for(school, fm)

    {:ok, view, html} = live(conn, ~p"/school/classes/#{cg.id}/discipline")

    assert html =~ "Awa Nkolo"
    refute has_element?(view, "#discipline-add-form")
    refute has_element?(view, "#delete-sanction-#{enrollment.id}")
    # Read only: no way to the conduct entry page.
    refute has_element?(view, "#conduct-link")

    view
    |> render_hook("add_sanction", %{
      "enrollment_id" => enrollment.id,
      "type" => "avertissement",
      "date" => "2025-09-10",
      "reason" => "forged"
    })

    sequence =
      Organization.current_sequence(
        scope,
        Organization.current_academic_year(scope),
        ~D[2025-09-10]
      )

    assert Discipline.list_sanctions(scope, cg, {:sequence, sequence}) == []
    assert Discipline.note_de_conduite(scope, enrollment, {:sequence, sequence}) == nil
  end

  test "a plain teacher who is not the form master is redirected to /school", %{
    school: school,
    cg: cg,
    head: head
  } do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(other.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

    conn = conn_for(school, other)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}/discipline")
  end

  test "cross-school class id redirects to /school/classes", %{conn: conn} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, os} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: other}, %{name: "Autre"})

    other_scope = school_scope(other, os)

    {:ok, oy} =
      Organization.create_academic_year(other_scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} = Enrollment.create_class_group(other_scope, oy, %{label: "6e Z", level: "6ème"})

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}/discipline")
  end

  test "a type not in use is not offered and a crafted one is refused", %{
    conn: conn,
    cg: cg,
    scope: scope,
    year: year,
    enrollment: enrollment
  } do
    {:ok, _} =
      Discipline.add_sanction(scope, enrollment, %{
        type: :consigne,
        date: ~D[2025-09-10],
        duration_hours: 2
      })

    {:ok, profile} = Accounts.fetch_school_profile(scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(
        :update_school_life,
        %{sanction_types_in_use: [:avertissement, :blame]},
        scope: scope
      )
      |> Ash.update()

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/discipline?period=annee")
    refute has_element?(view, "#discipline-type-select option[value='consigne']")
    assert has_element?(view, "#discipline-type-select option[value='blame']")

    count = fn -> length(Discipline.list_sanctions(scope, enrollment, {:annual, year})) end
    before = count.()

    view
    |> element("#discipline-add-form")
    |> render_submit(%{
      "enrollment_id" => enrollment.id,
      "type" => "consigne",
      "date" => "2025-09-12"
    })

    assert count.() == before
  end
end
