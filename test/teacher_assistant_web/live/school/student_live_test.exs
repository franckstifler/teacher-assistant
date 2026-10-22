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

    # The form stays folded until « + Ajouter ».
    refute has_element?(view, "#guardian-form")
    view |> element("#add-guardian") |> render_click()

    # Typing the sibling's number offers the existing parent instead of a new record.
    view |> form("#guardian-form", guardian: %{phone: "+237 677 12 34 56"}) |> render_change()

    assert view |> element("#guardian-match") |> render() =~ "— père de 1 élève (6e A)"

    view |> element("#guardian-match button") |> render_click()
    assert view |> element("#guardian-list") |> render() =~ "Contact principal"
    refute has_element?(view, "#guardian-form")

    [jean_link] = Enrollment.list_guardian_links(scope, awa)

    assert view |> element("#guardian-meta-#{jean_link.id}") |> render() =~
             "aussi parent de Paul Nkolo (6e A)"

    view |> element("#add-guardian") |> render_click()

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

  test "the header shows the class, the age and the class's links", %{
    conn: conn,
    cg: cg,
    awa: awa
  } do
    {:ok, view, _html} = live(conn, ~p"/school/students/#{awa.id}")

    assert view |> element("#student-breadcrumb a[href='/school/students']") |> has_element?()
    assert view |> element("#student-class") |> render() =~ "6e A"

    today = Date.utc_today()
    years = today.year - 2013 - if({today.month, today.day} < {4, 2}, do: 1, else: 0)
    assert view |> element("#student-sex-age") |> render() =~ "Féminin · #{years} ans"

    assert has_element?(view, "#student-bulletin")
    assert has_element?(view, ~s|#student-absences[href="/school/classes/#{cg.id}/register"]|)
    assert view |> element("#this-year-unjustified") |> render() =~ "0 h"
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
    refute has_element?(view, "#add-guardian")
    refute has_element?(view, "#guardian-form")
    refute has_element?(view, "#student-breadcrumb a")
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

  test "the admin edits a guardian in place", %{conn: conn, scope: scope, awa: awa} do
    {:ok, _} =
      Enrollment.add_guardian(scope, awa, %{
        full_name: "Jean Nkolo",
        relationship: :pere,
        phone: "677123456"
      })

    [link] = Enrollment.list_guardian_links(scope, awa)
    {:ok, view, _html} = live(conn, ~p"/school/students/#{awa.id}")

    view |> element("#edit-guardian-#{link.id}") |> render_click()

    view
    |> form("#guardian-edit-form",
      guardian: %{phone: "699 88 77 66", full_name: "Jean-Pierre Nkolo"}
    )
    |> render_submit()

    assert [
             %{
               primary_contact: true,
               guardian: %{full_name: "Jean-Pierre Nkolo", phone_key: "699887766"}
             }
           ] =
             Enrollment.list_guardian_links(scope, awa)

    refute has_element?(view, "#guardian-edit-form")
  end

  describe "photo" do
    test "the SG uploads the student's photo from the profile", %{
      scope: scope,
      school: school,
      awa: awa
    } do
      sg = member_scope_fixture(scope, %{roles: [:discipline_master]})
      {:ok, view, _html} = live(conn_for(school, sg.current_user), ~p"/school/students/#{awa.id}")

      view |> element("#student-photo-button") |> render_click()
      assert has_element?(view, "#photo-sheet")

      view
      |> file_input("#photo-upload-form", :photo, [
        %{
          name: "#{awa.id}.jpg",
          content: File.read!("test/support/fixtures/files/1x1.jpg"),
          type: "image/jpeg"
        }
      ])
      |> render_upload("#{awa.id}.jpg")

      assert {:ok, %{photo_path: path}} = Enrollment.fetch_owned_student(scope, awa.id)
      assert is_binary(path)
      assert_push_event(view, "photo:stored", %{student_id: student_id})
      assert student_id == awa.id

      assert has_element?(
               view,
               ~s(#student-header img[src^="/school/students/#{awa.id}/photo?v="])
             )
    end

    test "a photo named after another student is refused", %{
      conn: conn,
      scope: scope,
      cg: cg,
      awa: awa
    } do
      {:ok, ben} = Enrollment.add_student(scope, cg, %{full_name: "Ben", sex: :m})
      {:ok, view, _html} = live(conn, ~p"/school/students/#{awa.id}")

      html =
        view
        |> file_input("#photo-upload-form", :photo, [
          %{
            name: "#{ben.id}.jpg",
            content: File.read!("test/support/fixtures/files/1x1.jpg"),
            type: "image/jpeg"
          }
        ])
        |> render_upload("#{ben.id}.jpg")

      assert html =~ "ne correspond pas"
      assert {:ok, %{photo_path: nil}} = Enrollment.fetch_owned_student(scope, ben.id)
    end

    test "the student's teacher cannot change the photo", %{
      scope: scope,
      school: school,
      cg: cg,
      awa: awa
    } do
      %{teacher: teacher} = school_teacher_fixture(scope, %{class_group: cg})
      {:ok, view, _html} = live(conn_for(school, teacher), ~p"/school/students/#{awa.id}")

      refute has_element?(view, "#student-photo-button")
      refute has_element?(view, "#photo-upload-form")
    end

    test "the ID card link targets the current class", %{conn: conn, cg: cg, awa: awa} do
      {:ok, view, _html} = live(conn, ~p"/school/students/#{awa.id}")

      assert has_element?(
               view,
               ~s(#student-card[href="/school/classes/#{cg.id}/cards/print?student=#{awa.id}"])
             )
    end
  end

  test "edits and shows the national ID", %{conn: conn, scope: scope, awa: awa} do
    {:ok, view, _html} = live(conn, ~p"/school/students/#{awa.id}")
    view |> element("#edit-identity") |> render_click()

    view
    |> form("#identity-form", student: %{national_id: "241592812"})
    |> render_submit()

    {:ok, awa} = Enrollment.fetch_owned_student(scope, awa.id)
    assert awa.national_id == "241592812"
    assert has_element?(view, "#student-national-id", "241592812")
  end
end
