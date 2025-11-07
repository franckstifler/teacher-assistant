defmodule TeacherAssistantWeb.AcademicYearLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  @create_attrs %{
    name: Faker.Team.creature(),
    description: Faker.Lorem.sentence(),
    start_date: Faker.Date.backward(250),
    end_date: Faker.Date.backward(50),
    terms: %{
      0 => %{
        name: "1st Term",
        start_date: Faker.Date.backward(150),
        end_date: Faker.Date.backward(70)
      },
      1 => %{
        name: "Second Term",
        start_date: Faker.Date.backward(100),
        end_date: Faker.Date.backward(10)
      }
    }
  }
  @update_attrs %{
    name: Faker.Cat.name(),
    description: Faker.Lorem.sentence(),
    start_date: Faker.Date.backward(200),
    end_date: Faker.Date.backward(100),
    terms: %{
      0 => %{
        name: Faker.Airports.name(),
        start_date: Faker.Date.backward(150),
        end_date: Faker.Date.backward(70)
      },
      1 => %{
        name: Faker.Airports.name(),
        start_date: Faker.Date.backward(100),
        end_date: Faker.Date.backward(10)
      }
    }
  }
  @invalid_attrs %{name: nil, description: nil, start_date: nil, end_date: nil}

  defp create_academic_year(%{tenant: tenant}) do
    academic_year = generate(academic_year(tenant: tenant))

    %{academic_year: academic_year}
  end

  describe "Index" do
    setup [:register_and_log_in_user, :create_academic_year]

    test "lists all academic_years", %{conn: conn, academic_year: academic_year} do
      {:ok, _index_live, html} = live(conn, ~p"/configurations/academic_years")

      assert html =~ "Listing Academic Years"
      assert html =~ academic_year.name
    end

    test "saves new academic_year", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/academic_years")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Academic Year")
               |> render_click()
               |> follow_redirect(conn, ~p"/configurations/academic_years/new")

      assert render(form_live) =~ "New Academic Year"

      assert form_live
             |> form("#academic_year-form", academic_year: @invalid_attrs)
             |> render_change() =~ "is required"

      # Click on label to add term.
      update_nested_form(form_live, "#academic_year-form", "academic_year[_add_terms]")
      update_nested_form(form_live, "#academic_year-form", "academic_year[_add_terms]")

      assert {:ok, index_live, _html} =
               form_live
               |> form("#academic_year-form", academic_year: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn)

      html = render(index_live)
      assert html =~ "Academic Year created successfully"
      assert html =~ @create_attrs.name
      assert html =~ @create_attrs.description

      @create_attrs.terms
      |> Enum.each(fn {_key, term} ->
        assert html =~ term.name
        assert html =~ Date.to_iso8601(term.start_date)
        assert html =~ Date.to_iso8601(term.end_date)
      end)
    end

    test "updates academic_year in listing", %{conn: conn, academic_year: academic_year} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/academic_years")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#academic_years-#{academic_year.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/configurations/academic_years/#{academic_year}/edit")

      assert render(form_live) =~ "Edit Academic Year"

      assert form_live
             |> form("#academic_year-form", academic_year: @invalid_attrs)
             |> render_change() =~ "is required"

      # update_nested_form(form_live, "#academic_year-form", "academic_year[_drop_terms][]", 0)
      update_nested_form(form_live, "#academic_year-form", "academic_year[_add_terms]")

      assert {:ok, index_live, _html} =
               form_live
               |> form("#academic_year-form", academic_year: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn)

      html = render(index_live)
      assert html =~ "Academic Year updated successfully"
      assert html =~ @update_attrs.name
      assert html =~ @update_attrs.description

      # Old term has been updated.
      [term] = academic_year.terms
      refute html =~ term.name

      @update_attrs.terms
      |> Enum.each(fn {_key, term} ->
        assert html =~ term.name
        assert html =~ Date.to_iso8601(term.start_date)
        assert html =~ Date.to_iso8601(term.end_date)
      end)
    end

    test "deletes academic_year in listing", %{conn: conn, academic_year: academic_year} do
      {:ok, index_live, _html} = live(conn, ~p"/configurations/academic_years")

      assert index_live
             |> element("#academic_years-#{academic_year.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#academic_years-#{academic_year.id}")
    end
  end

  describe "Show" do
    setup [:register_and_log_in_user, :create_academic_year]

    test "displays academic_year", %{conn: conn, academic_year: academic_year} do
      {:ok, _show_live, html} = live(conn, ~p"/configurations/academic_years/#{academic_year}")

      assert html =~ "Show Academic Year"
      assert html =~ academic_year.name
    end

    test "updates academic_year and returns to show", %{conn: conn, academic_year: academic_year} do
      {:ok, show_live, _html} = live(conn, ~p"/configurations/academic_years/#{academic_year}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(
                 conn,
                 ~p"/configurations/academic_years/#{academic_year}/edit?return_to=show"
               )

      assert render(form_live) =~ "Edit Academic Year"

      assert form_live
             |> form("#academic_year-form", academic_year: @invalid_attrs)
             |> render_change() =~ "is required"

      update_nested_form(form_live, "#academic_year-form", "academic_year[_add_terms]")

      assert {:ok, show_live, _html} =
               form_live
               |> form("#academic_year-form", academic_year: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/configurations/academic_years/#{academic_year}")

      html = render(show_live)
      assert html =~ "Academic Year updated successfully"
      assert html =~ @update_attrs.name
      assert html =~ @update_attrs.description
    end

    test "updates academic_year classrooms", %{
      conn: conn,
      tenant: tenant,
      academic_year: academic_year
    } do
      {:ok, show_live, _html} = live(conn, ~p"/configurations/academic_years/#{academic_year}")

      [level_option_1, level_option_2, level_option_3] =
        generate_many(level_option(tenant: tenant), 3)
        |> Ash.load!(:full_name)

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Manage classrooms")
               |> render_click()
               |> follow_redirect(
                 conn,
                 ~p"/configurations/academic_years/#{academic_year}/manage_classrooms"
               )

      assert render(form_live) =~ "Edit Year Classrooms"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#academic_year-form",
                 academic_year: %{levels_options: [level_option_1.id, level_option_2.id]}
               )
               |> render_submit()
               |> follow_redirect(conn, ~p"/configurations/academic_years/#{academic_year}")

      html = render(show_live)
      assert html =~ "Classrooms updated successfully"
      assert html =~ level_option_1.full_name
      assert html =~ level_option_2.full_name
      refute html =~ level_option_3.full_name
    end
  end
end
