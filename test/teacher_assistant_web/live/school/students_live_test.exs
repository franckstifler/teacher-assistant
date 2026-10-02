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

    {:ok, _} = Enrollment.add_student(scope, sixth, %{full_name: "Zoé Abena", sex: :f})
    {:ok, _} = Enrollment.add_guardian(scope, awa, %{full_name: "Jean Nkolo", relationship: :pere, phone: "677123456"})

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, scope: scope, school: school, sixth: sixth, awa: awa}
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

  test "a plain teacher is sent back to the school home", %{school: school, scope: scope} do
    teacher = member_scope_fixture(scope, %{roles: [:teacher]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, teacher.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/students")
  end
end
