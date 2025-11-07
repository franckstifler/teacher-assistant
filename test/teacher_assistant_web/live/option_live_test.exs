defmodule TeacherAssistantWeb.OptionLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  @create_attrs %{name: Faker.Cat.name(), description: Faker.Lorem.word()}
  @update_attrs %{name: Faker.Cat.name(), description: Faker.Lorem.word()}
  @invalid_attrs %{name: nil, description: nil}
  defp create_option(%{tenant: tenant}) do
    option = generate(option(tenant: tenant))

    %{option: option}
  end

  describe "Index" do
    setup [:register_and_log_in_user, :create_option]

    test "lists all options", %{conn: conn, option: option} do
      {:ok, _index_live, html} = live(conn, ~p"/configurations/options")

      assert html =~ "Listing Options"
      assert html =~ to_string(option.name)
    end

    test "saves new option", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/options")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Option")
               |> render_click()
               |> follow_redirect(conn, ~p"/configurations/options/new")

      assert render(form_live) =~ "New Option"

      assert form_live
             |> form("#option-form", option: @invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#option-form", option: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn)

      html = render(index_live)
      assert html =~ "Option created successfully"
      assert html =~ @create_attrs.name
      assert html =~ @create_attrs.description
    end

    test "updates option in listing", %{conn: conn, option: option} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/options")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#options-#{option.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/configurations/options/#{option}/edit")

      assert render(form_live) =~ "Edit Option"

      assert form_live
             |> form("#option-form", option: @invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#option-form", option: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn)

      html = render(index_live)
      assert html =~ "Option updated successfully"
      assert html =~ @update_attrs.name
      assert html =~ @update_attrs.description
    end

    test "deletes option in listing", %{conn: conn, option: option} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/options")

      assert index_live |> element("#options-#{option.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#options-#{option.id}")
    end
  end

  describe "Show" do
    setup [:register_and_log_in_user, :create_option]

    test "displays option", %{conn: conn, option: option} do
      {:ok, show_live, html} = live(conn, ~p"/configurations/options/#{option}")

      open_browser(show_live)
      assert html =~ "Show Option"
      assert html =~ to_string(option.name)
    end

    test "updates option and returns to show", %{conn: conn, option: option} do
      {:ok, show_live, _html} = live(conn, ~p"/configurations/options/#{option}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/configurations/options/#{option}/edit?return_to=show")

      assert render(form_live) =~ "Edit Option"

      assert form_live
             |> form("#option-form", option: @invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#option-form", option: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/configurations/options/#{option}")

      html = render(show_live)
      assert html =~ "Option updated successfully"
      assert html =~ @update_attrs.name
      assert html =~ @update_attrs.description
    end
  end
end
