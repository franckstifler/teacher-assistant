defmodule TeacherAssistantWeb.School.DisciplineLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Discipline
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} = Schools.create_school(head, %{name: "Lycée D"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Academics.build_default_calendar(year)

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})

    {:ok, _student} = Academics.add_student(cg, %{full_name: "Awa Nkolo", sex: :f})
    [%{enrollment: enrollment}] = Academics.list_roster(cg)

    sequence = Academics.current_sequence(year, ~D[2025-09-08])

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      school: school,
      year: year,
      cg: cg,
      head: head,
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
    enrollment: enrollment
  } do
    dm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{
        email: to_string(dm.email),
        roles: [:discipline_master]
      })

    {:ok, _} = Schools.accept_invitation(inv.token, dm)

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
        cg,
        {:sequence,
         Academics.current_sequence(
           TeacherAssistant.Academics.current_academic_year(school),
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
             cg,
             {:sequence,
              Academics.current_sequence(
                TeacherAssistant.Academics.current_academic_year(school),
                ~D[2025-09-10]
              )}
           ) == []
  end

  test "an exclusion temporaire sanction stores its duration", %{
    school: school,
    cg: cg,
    head: head,
    enrollment: enrollment
  } do
    dm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{
        email: to_string(dm.email),
        roles: [:discipline_master]
      })

    {:ok, _} = Schools.accept_invitation(inv.token, dm)

    conn = conn_for(school, dm)

    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/discipline")

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
        cg,
        {:sequence,
         Academics.current_sequence(
           TeacherAssistant.Academics.current_academic_year(school),
           ~D[2025-09-10]
         )}
      )

    assert sanction.type == :exclusion_temporaire
    assert sanction.duration_days == 3
  end

  test "a conduct manager sets a note de conduite that persists", %{
    school: school,
    cg: cg,
    head: head,
    enrollment: enrollment,
    sequence: sequence
  } do
    dm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{
        email: to_string(dm.email),
        roles: [:discipline_master]
      })

    {:ok, _} = Schools.accept_invitation(inv.token, dm)

    conn = conn_for(school, dm)

    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/discipline")

    view
    |> form("#note-form-#{enrollment.id}", %{"value" => "15"})
    |> render_submit()

    assert Decimal.equal?(
             Discipline.note_de_conduite(enrollment, {:sequence, sequence}),
             Decimal.new(15)
           )
  end

  test "the period selector reloads the sanctions log", %{
    conn: _conn,
    school: school,
    cg: cg,
    year: year,
    head: head,
    enrollment: enrollment
  } do
    {:ok, _sanction} =
      Discipline.add_sanction(
        enrollment,
        %{type: :blame, date: ~D[2025-09-10], reason: "Retard"},
        head.id
      )

    sequence = Academics.current_sequence(year, ~D[2025-09-10])
    other_sequences = Academics.list_sequences(year) |> Enum.reject(&(&1.id == sequence.id))

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
    enrollment: enrollment
  } do
    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(fm.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, fm)
    {:ok, _} = Academics.set_form_master(cg, fm.id)

    conn = conn_for(school, fm)

    {:ok, view, html} = live(conn, ~p"/school/classes/#{cg.id}/discipline")

    assert html =~ "Awa Nkolo"
    refute has_element?(view, "#discipline-add-form")
    refute has_element?(view, "#delete-sanction-#{enrollment.id}")

    view
    |> render_hook("add_sanction", %{
      "enrollment_id" => enrollment.id,
      "type" => "avertissement",
      "date" => "2025-09-10",
      "reason" => "forged"
    })

    view
    |> render_hook("set_note", %{"enrollment_id" => enrollment.id, "value" => "10"})

    sequence =
      Academics.current_sequence(
        TeacherAssistant.Academics.current_academic_year(school),
        ~D[2025-09-10]
      )

    assert Discipline.list_sanctions(cg, {:sequence, sequence}) == []
    assert Discipline.note_de_conduite(enrollment, {:sequence, sequence}) == nil
  end

  test "a plain teacher who is not the form master is redirected to /school", %{
    school: school,
    cg: cg,
    head: head
  } do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn = conn_for(school, other)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}/discipline")
  end

  test "cross-school class id redirects to /school/classes", %{conn: conn} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, os} = Schools.create_school(other, %{name: "Autre"})

    {:ok, oy} =
      Academics.create_academic_year(os, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} = Academics.create_class_group(os, oy, %{label: "6e Z", level: "6ème"})

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}/discipline")
  end
end
