defmodule TeacherAssistantWeb.SubjectLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  @create_attrs %{
    name: Faker.Cat.name(),
    default_coefficient: 1,
    description: Faker.Lorem.word()
  }
  @update_attrs %{name: Faker.Cat.name(), default_coefficient: 5, description: Faker.Lorem.word()}
  @invalid_attrs %{name: nil, default_coefficient: nil, description: nil}
  defp create_subject(%{tenant: tenant}) do
    subject = generate(subject(tenant: tenant))

    %{subject: subject}
  end

  describe "Index" do
    setup [:register_and_log_in_user, :create_subject]

    test "lists all subjects", %{conn: conn, subject: subject} do
      {:ok, _index_live, html} = live(conn, ~p"/configurations/subjects")

      assert html =~ "Listing Subjects"
      assert html =~ to_string(subject.name)
    end

    test "saves new subject", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/subjects")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Subject")
               |> render_click()
               |> follow_redirect(conn, ~p"/configurations/subjects/new")

      assert render(form_live) =~ "New Subject"

      assert form_live
             |> form("#subject-form", subject: @invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#subject-form", subject: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn)

      html = render(index_live)
      assert html =~ "Subject created successfully"
      assert html =~ @create_attrs.name
      assert html =~ to_string(@create_attrs.default_coefficient)
      assert html =~ @create_attrs.description
    end

    test "updates subject in listing", %{conn: conn, subject: subject} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/subjects")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#subjects-#{subject.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/configurations/subjects/#{subject}/edit")

      assert render(form_live) =~ "Edit Subject"

      assert form_live
             |> form("#subject-form", subject: @invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#subject-form", subject: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn)

      html = render(index_live)
      assert html =~ "Subject updated successfully"
      assert html =~ @update_attrs.name
      assert html =~ to_string(@update_attrs.default_coefficient)
      assert html =~ @update_attrs.description
    end

    test "deletes subject in listing", %{conn: conn, subject: subject} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/subjects")

      assert index_live |> element("#subjects-#{subject.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#subjects-#{subject.id}")
    end
  end

  describe "Show" do
    setup [:register_and_log_in_user, :create_subject]

    test "displays subject", %{conn: conn, subject: subject} do
      {:ok, _show_live, html} = live(conn, ~p"/configurations/subjects/#{subject}")

      assert html =~ "Show Subject"
      assert html =~ to_string(subject.name)
    end

    test "updates subject and returns to show", %{conn: conn, subject: subject} do
      {:ok, show_live, _html} = live(conn, ~p"/configurations/subjects/#{subject}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(
                 conn,
                 ~p"/configurations/subjects/#{subject}/edit?return_to=show"
               )

      assert render(form_live) =~ "Edit Subject"

      assert form_live
             |> form("#subject-form", subject: @invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#subject-form", subject: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/configurations/subjects/#{subject}")

      html = render(show_live)
      assert html =~ "Subject updated successfully"
      assert html =~ @update_attrs.name
      assert html =~ to_string(@update_attrs.default_coefficient)
      assert html =~ @update_attrs.description
    end
  end
end
