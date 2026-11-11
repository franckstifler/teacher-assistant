defmodule TeacherAssistantWeb.School.StudentsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Enrollment, Organization}

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée E"})

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, sixth} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, fifth} = Enrollment.create_class_group(scope, year, %{label: "5e A", level: "5ème"})

    {:ok, awa} =
      Enrollment.add_student(scope, fifth, %{full_name: "Awa Nkolo", sex: :f, matricule: "M-001"})

    {:ok, zoe} = Enrollment.add_student(scope, sixth, %{full_name: "Zoé Abena", sex: :f})

    {:ok, _} =
      Enrollment.add_guardian(scope, awa, %{
        full_name: "Jean Nkolo",
        relationship: :pere,
        phone: "677123456"
      })

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, scope: scope, school: school, sixth: sixth, fifth: fifth, awa: awa, zoe: zoe}
  end

  test "lists the year's students in class order with their main contact", %{conn: conn, awa: awa} do
    {:ok, view, _html} = live(conn, ~p"/school/students")

    rows = view |> element("#student-rows") |> render()
    assert rows =~ "Zoé Abena"
    assert rows =~ "Awa Nkolo"
    # 6e before 5e (school ladder order).
    assert :binary.match(rows, "Zoé Abena") < :binary.match(rows, "Awa Nkolo")
    assert rows =~ "Jean Nkolo"
    assert rows =~ "tel:677123456"
    assert has_element?(view, ~s|a[href="/school/students/#{awa.id}"]|)
  end

  test "searches by name or matricule and filters by class", %{conn: conn, sixth: sixth} do
    {:ok, view, _html} = live(conn, ~p"/school/students?q=M-001")
    assert render(view) =~ "Awa Nkolo"
    refute render(view) =~ "Zoé Abena"

    {:ok, view, _html} = live(conn, ~p"/school/students?q=abe")
    assert render(view) =~ "Zoé Abena"
    refute render(view) =~ "Awa Nkolo"

    {:ok, view, _html} = live(conn, ~p"/school/students?class=#{sixth.id}")
    assert render(view) =~ "Zoé Abena"
    refute render(view) =~ "Awa Nkolo"
  end

  test "the header counts the year, the banner the parent contacts", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/school/students?q=awa")

    # Independent of the active filters.
    assert view |> element("#students-subtitle") |> render() =~ "2025-2026 · 2 inscrits"
    assert view |> element("#contacts-banner") |> render() =~ "Contacts parents : 1 sur 2"
  end

  test "the banner leads to the students with no parent, and back", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/school/students")
    assert view |> element("#no-contact-link") |> render() =~ "Voir l&#39;élève sans contact"

    view |> element("#no-contact-link") |> render_click()
    assert_patch(view, ~p"/school/students?no_contact=1")

    rows = view |> element("#student-rows") |> render()
    assert rows =~ "Zoé Abena"
    assert rows =~ "+ Ajouter"
    refute rows =~ "Awa Nkolo"
    assert has_element?(view, "#no-contact-link[aria-pressed=true]", "Voir tous les élèves")

    view |> element("#no-contact-link") |> render_click()
    assert_patch(view, ~p"/school/students")
  end

  test "the banner offers the chosen class's import", %{conn: conn, sixth: sixth} do
    {:ok, view, _html} = live(conn, ~p"/school/students")
    assert has_element?(view, "#import-contacts-hint")

    {:ok, view, _html} = live(conn, ~p"/school/students?class=#{sixth.id}")

    assert has_element?(
             view,
             ~s|#import-contacts-link[href="/school/classes/#{sixth.id}/import"]|,
             "6e A"
           )
  end

  test "« + Ajouter » opens the student with no contact", %{conn: conn, zoe: zoe} do
    {:ok, view, _html} = live(conn, ~p"/school/students")
    assert has_element?(view, ~s|#add-contact-#{zoe.id}[href="/school/students/#{zoe.id}"]|)
  end

  test "« Redoublants » and « Sans photo » filter the list", ctx do
    %{conn: conn, scope: scope, fifth: fifth} = ctx

    {:ok, bob} =
      Enrollment.add_student(scope, fifth, %{full_name: "Bob Ndi", sex: :m, repeater: true})

    {:ok, view, _html} = live(conn, ~p"/school/students")
    assert has_element?(view, "#repeater-pill", "1")
    assert has_element?(view, "#no-photo-pill", "3")
    assert view |> element("#student-#{bob.id}") |> render() =~ "· redoublant"

    view |> element("#repeater-pill") |> render_click()
    assert_patch(view, ~p"/school/students?repeater=1")
    rows = view |> element("#student-rows") |> render()
    assert rows =~ "Bob Ndi"
    refute rows =~ "Zoé Abena"
    assert has_element?(view, "#repeater-pill[aria-current]")

    {:ok, view, _html} = live(conn, ~p"/school/students?no_photo=1")
    assert view |> element("#student-rows") |> render() =~ "Zoé Abena"
  end

  test "« Partis » lists departed students with their date; the default list hides them (A7)",
       ctx do
    %{conn: conn, scope: scope, zoe: zoe} = ctx
    [e] = Enrollment.student_history(scope, zoe)
    {:ok, _} = Enrollment.leave(scope, e, %{departure_reason: :transfer})

    {:ok, view, _html} = live(conn, ~p"/school/students")
    refute view |> element("#student-rows") |> render() =~ "Zoé Abena"
    assert has_element?(view, "#departed-pill", "1")

    view |> element("#departed-pill") |> render_click()
    assert_patch(view, ~p"/school/students?departed=1")
    rows = view |> element("#student-rows") |> render()
    assert rows =~ "Zoé Abena"
    assert rows =~ "parti(e) le"
  end

  test "in English the pill reads « Departed » (minors)", ctx do
    %{conn: conn, scope: scope, zoe: zoe} = ctx
    [e] = Enrollment.student_history(scope, zoe)
    {:ok, _} = Enrollment.leave(scope, e, %{departure_reason: :transfer})
    conn = get(conn, ~p"/locale/en")

    {:ok, view, _html} = live(recycle(conn), ~p"/school/students")
    assert has_element?(view, "#departed-pill", "Departed")
  end

  test "the class select groups classes by level", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/school/students")
    assert has_element?(view, "#students-class-select optgroup[label='6ème'] option", "6e A")
    assert has_element?(view, "#students-class-select optgroup[label='5ème'] option", "5e A")
  end

  test "a student whose main contact was removed counts as without contact", ctx do
    %{conn: conn, scope: scope, awa: awa} = ctx

    {:ok, _} =
      Enrollment.add_guardian(scope, awa, %{
        full_name: "Marie Nkolo",
        relationship: :mere,
        phone: "699000001"
      })

    [jean | _] = Enrollment.list_guardian_links(scope, awa)
    :ok = Enrollment.unlink_guardian(scope, jean)

    {:ok, view, _html} = live(conn, ~p"/school/students?no_contact=1")
    assert view |> element("#student-rows") |> render() =~ "Awa Nkolo"
    assert view |> element("#contacts-banner") |> render() =~ "Contacts parents : 0 sur 2"
  end

  test "a page past the end shows the last page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/school/students?page=99")
    assert view |> element("#students-range") |> render() =~ "1–2 sur 2"
  end

  test "rows show the sex under the name, the class and a range footer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/school/students")

    rows = view |> element("#student-rows") |> render()
    assert rows =~ "Féminin"
    assert rows =~ "6e A"
    assert view |> element("#students-range") |> render() =~ "1–2 sur 2"
    refute has_element?(view, "#students-next")
  end

  test "clicking a row opens the student", %{conn: conn, awa: awa} do
    {:ok, view, _html} = live(conn, ~p"/school/students")

    assert view |> element("#student-#{awa.id}") |> render() =~
             ~s|phx-click="[[&quot;navigate&quot;|
  end

  describe "« Inscrire un élève »" do
    test "picks the class first, then enrols", %{conn: conn, scope: scope, sixth: sixth} do
      {:ok, view, _html} = live(conn, ~p"/school/students")
      view |> element("#enroll-button") |> render_click()

      assert view |> element("#enroll-class") |> render() =~ "6e A — 1 élève"

      view
      |> form("#enroll-form", %{"enroll" => %{"full_name" => "Mbida Paul", "sex" => "m"}})
      |> render_submit()

      assert view |> element("#enroll-error") |> render() =~ "Choisissez une classe."

      view |> form("#enroll-class-form", %{"class_id" => sixth.id}) |> render_change()
      assert view |> element("#enroll-drawer") |> render() =~ "6e A · 1 élève"

      view
      |> form("#enroll-form", %{"enroll" => %{"full_name" => "Mbida Paul", "sex" => "m"}})
      |> render_submit()

      refute has_element?(view, "#enroll-drawer")
      assert render(view) =~ "Élève inscrit en 6e A"
      assert view |> element("#student-rows") |> render() =~ "Mbida Paul"
      assert view |> element("#students-subtitle") |> render() =~ "3 inscrits"

      assert Enum.any?(
               Enrollment.list_roster(scope, sixth),
               &(&1.student.full_name == "Mbida Paul")
             )
    end

    test "« Inscrire et en ajouter un autre » keeps the class and counts the new student",
         %{conn: conn, sixth: sixth} do
      {:ok, view, _html} = live(conn, ~p"/school/students")
      view |> element("#enroll-button") |> render_click()
      view |> form("#enroll-class-form", %{"class_id" => sixth.id}) |> render_change()

      view
      |> form("#enroll-form", %{"enroll" => %{"full_name" => "Mbida Paul", "sex" => "m"}})
      |> render_submit(%{"then" => "another"})

      assert has_element?(view, "#enroll-drawer")
      assert view |> element("#enroll-class") |> render() =~ "6e A — 2 élèves"
      assert view |> element("#enroll-drawer") |> render() =~ "6e A · 2 élèves"
    end

    test "is offered to class managers only", %{school: school, scope: scope} do
      sg = member_scope_fixture(scope, %{roles: [:discipline_master]})

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_user_in_session(sg.current_user)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      {:ok, view, _html} = live(conn, ~p"/school/students")
      refute has_element?(view, "#enroll-button")
    end
  end

  test "a plain teacher is sent back to the school home", %{school: school, scope: scope} do
    teacher = member_scope_fixture(scope, %{roles: [:teacher]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> put_user_in_session(teacher.current_user)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/students")
  end
end
