defmodule TeacherAssistantWeb.LevelLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  @create_attrs %{name: Faker.Cat.name(), description: Faker.Lorem.word()}
  @update_attrs %{name: Faker.Cat.name(), description: Faker.Lorem.word()}
  @invalid_attrs %{name: nil, description: nil}
  defp create_level(%{tenant: tenant}) do
    level = generate(level(tenant: tenant))

    %{level: level}
  end

  describe "Index" do
    setup [:register_and_log_in_user, :create_level]

    test "lists all levels", %{conn: conn, level: level} do
      {:ok, _index_live, html} = live(conn, ~p"/configurations/levels")

      assert html =~ "Listing Levels"
      assert html =~ level.name
    end

    test "saves new level", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/levels")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Level")
               |> render_click()
               |> follow_redirect(conn, ~p"/configurations/levels/new")

      assert render(form_live) =~ "New Level"

      assert form_live
             |> form("#level-form", level: @invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#level-form", level: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn)

      html = render(index_live)
      assert html =~ "Level created successfully"
      assert html =~ @create_attrs.name
      assert html =~ @create_attrs.description
    end

    test "updates level in listing", %{conn: conn, level: level} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/levels")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#levels-#{level.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/configurations/levels/#{level}/edit")

      assert render(form_live) =~ "Edit Level"

      assert form_live
             |> form("#level-form", level: @invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#level-form", level: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn)

      html = render(index_live)
      assert html =~ "Level updated successfully"
      assert html =~ @update_attrs.name
      assert html =~ @update_attrs.description
    end

    test "deletes level in listing", %{conn: conn, level: level} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/levels")

      assert index_live |> element("#levels-#{level.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#levels-#{level.id}")
    end
  end

  describe "Show" do
    setup [:register_and_log_in_user, :create_level]

    test "displays level", %{conn: conn, level: level} do
      {:ok, _show_live, html} = live(conn, ~p"/configurations/levels/#{level}")

      assert html =~ "Show Level"
      assert html =~ level.name
    end

    test "updates level and returns to show", %{conn: conn, level: level} do
      {:ok, show_live, _html} = live(conn, ~p"/configurations/levels/#{level}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/configurations/levels/#{level}/edit?return_to=show")

      assert render(form_live) =~ "Edit Level"

      assert form_live
             |> form("#level-form", level: @invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#level-form", level: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/configurations/levels/#{level}")

      html = render(show_live)
      assert html =~ "Level updated successfully"
      assert html =~ @update_attrs.name
      assert html =~ @update_attrs.description
    end
  end
end
