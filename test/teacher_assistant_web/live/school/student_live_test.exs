defmodule TeacherAssistantWeb.School.StudentLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Enrollment, Organization}

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée F"})

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
    {:ok, other} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})

    {:ok, awa} =
      Enrollment.add_student(scope, cg, %{
        full_name: "Awa Nkolo",
        sex: :f,
        birth_date: ~D[2013-04-02],
        birth_place: "Yaoundé"
      })

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, scope: scope, school: school, cg: cg, other: other, awa: awa}
  end

  defp conn_for(school, user) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  test "shows identity, history and this year's discipline", %{conn: conn, awa: awa} do
    {:ok, view, _html} = live(conn, ~p"/school/students/#{awa.id}")

    identity = view |> element("#student-identity") |> render()
    assert identity =~ "Awa Nkolo"
    assert identity =~ "02/04/2013"
    assert identity =~ "Yaoundé"

    assert view |> element("#student-history") |> render() =~ "6e A"
    assert view |> element("#student-this-year") |> render() =~ "0"
  end

  test "the admin adds a guardian, links a sibling's parent, changes the main contact", %{
    conn: conn,
    scope: scope,
    cg: cg,
    awa: awa
  } do
    {:ok, paul} = Enrollment.add_student(scope, cg, %{full_name: "Paul Nkolo", sex: :m})

    {:ok, _} =
      Enrollment.add_guardian(scope, paul, %{
        full_name: "Jean Nkolo",
        relationship: :pere,
        phone: "677123456"
      })

    {:ok, view, _html} = live(conn, ~p"/school/students/#{awa.id}")

    # Typing the sibling's number offers the existing parent instead of a new record.
    view |> form("#guardian-form", guardian: %{phone: "+237 677 12 34 56"}) |> render_change()
    assert has_element?(view, "#guardian-match", "Jean Nkolo")
    view |> element("#guardian-match button") |> render_click()
    assert view |> element("#guardian-list") |> render() =~ "Contact principal"

    view
    |> form("#guardian-form",
      guardian: %{
        full_name: "Marie Nkolo",
        relationship: "mere",
        phone: "699000001",
        language: "fr"
      }
    )
    |> render_submit()

    [_, marie] = Enrollment.list_guardian_links(scope, awa)
    view |> element("#make-primary-#{marie.id}") |> render_click()

    assert [%{guardian: %{full_name: "Marie Nkolo"}, primary_contact: true} | _] =
             Enrollment.list_guardian_links(scope, awa)
  end

  test "the admin edits the identity", %{conn: conn, scope: scope, awa: awa} do
    {:ok, view, _html} = live(conn, ~p"/school/students/#{awa.id}")
    view |> element("#edit-identity") |> render_click()

    view
    |> form("#identity-form", student: %{birth_place: "Douala"})
    |> render_submit()

    {:ok, awa} = Enrollment.fetch_owned_student(scope, awa.id)
    assert awa.birth_place == "Douala"
  end

  test "the student's teacher reads the profile without edit buttons", %{
    school: school,
    scope: scope,
    cg: cg,
    awa: awa
  } do
    %{teacher: teacher} = school_teacher_fixture(scope, %{class_group: cg})
    {:ok, view, _html} = live(conn_for(school, teacher), ~p"/school/students/#{awa.id}")

    assert render(view) =~ "Awa Nkolo"
    refute has_element?(view, "#edit-identity")
    refute has_element?(view, "#guardian-form")
  end

  test "a teacher of another class is sent back", %{
    school: school,
    scope: scope,
    other: other,
    awa: awa
  } do
    %{teacher: teacher} = school_teacher_fixture(scope, %{class_group: other})

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn_for(school, teacher), ~p"/school/students/#{awa.id}")
  end

  test "an unknown or foreign student id is sent back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school/students"}}} =
             live(conn, ~p"/school/students/#{Ash.UUID.generate()}")
  end
end
