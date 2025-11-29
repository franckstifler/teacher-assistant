defmodule TeacherAssistantWeb.StudentLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  @create_attrs %{
    first_name: Faker.Person.first_name(),
    last_name: Faker.Person.last_name(),
    matricule: "M-" <> Faker.String.base64(6),
    date_of_birth: Faker.Date.backward(500),
    place_of_birth: Faker.Address.city(),
    gender: :male
  }

  @update_attrs %{
    first_name: Faker.Person.first_name(),
    last_name: Faker.Person.last_name(),
    matricule: "M-" <> Faker.String.base64(6),
    date_of_birth: Faker.Date.backward(400),
    place_of_birth: Faker.Address.city(),
    gender: :female
  }

  @invalid_attrs %{
    first_name: nil,
    last_name: nil,
    date_of_birth: nil,
    gender: nil
  }

  defp create_student(%{tenant: tenant}) do
    student = generate(student(tenant: tenant))

    %{student: student}
  end

  describe "Index" do
    setup [:register_and_log_in_user, :create_student]

    test "lists all students", %{conn: conn, student: student} do
      {:ok, index_live, html} = live(conn, ~p"/configurations/students")

      assert html =~ "Listing Students"
      assert html =~ to_string(student.first_name)
      assert html =~ to_string(student.last_name)
    end

    test "saves new student", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/students")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Student")
               |> render_click()
               |> follow_redirect(conn, ~p"/configurations/students/new")

      assert render(form_live) =~ "New Student"

      assert form_live
             |> form("#student-form", student: @invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#student-form", student: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn)

      html = render(index_live)
      assert html =~ "Student created successfully"
      assert html =~ @create_attrs.first_name
      assert html =~ @create_attrs.last_name
      assert html =~ @create_attrs.matricule
    end

    test "updates student in listing", %{conn: conn, student: student} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/students")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#students-#{student.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/configurations/students/#{student}/edit")

      assert render(form_live) =~ "Edit Student"

      assert form_live
             |> form("#student-form", student: @invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#student-form", student: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn)

      html = render(index_live)
      assert html =~ "Student updated successfully"
      assert html =~ @update_attrs.first_name
      assert html =~ @update_attrs.last_name
      assert html =~ @update_attrs.matricule
    end

    test "deletes student in listing", %{conn: conn, student: student} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/students")

      assert index_live |> element("#students-#{student.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#students-#{student.id}")
    end
  end

  describe "Show" do
    setup [:register_and_log_in_user, :create_student]

    test "displays student", %{conn: conn, student: student} do
      {:ok, _show_live, html} = live(conn, ~p"/configurations/students/#{student}")

      assert html =~ "Show Student"
      assert html =~ to_string(student.first_name)
      assert html =~ to_string(student.last_name)
    end

    test "updates student and returns to show", %{conn: conn, student: student} do
      {:ok, show_live, _html} = live(conn, ~p"/configurations/students/#{student}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(
                 conn,
                 ~p"/configurations/students/#{student}/edit?return_to=show"
               )

      assert render(form_live) =~ "Edit Student"

      assert form_live
             |> form("#student-form", student: @invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#student-form", student: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/configurations/students/#{student}")

      html = render(show_live)
      assert html =~ "Student updated successfully"
      assert html =~ @update_attrs.first_name
      assert html =~ @update_attrs.last_name
      assert html =~ @update_attrs.matricule
    end
  end
end
