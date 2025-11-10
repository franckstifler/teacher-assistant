defmodule TeacherAssistantWeb.LevelOptionLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  defp create_level_option(%{tenant: tenant}) do
    level_option = generate(level_option(tenant: tenant))
    level_option = Ash.load!(level_option, [:option, :level, :full_name])

    %{level_option: level_option}
  end

  describe "Index" do
    setup [:register_and_log_in_user, :create_level_option]

    test "lists all levels_options", %{conn: conn, level_option: level_option} do
      {:ok, _index_live, html} = live(conn, ~p"/configurations/levels_options")

      assert html =~ "Listing LevelsOptions"
      assert html =~ level_option.full_name
    end
  end

  describe "Show" do
    setup [:register_and_log_in_user, :create_level_option]

    test "displays level_option", %{conn: conn, level_option: level_option} do
      {:ok, _show_live, html} = live(conn, ~p"/configurations/levels_options/#{level_option}")

      assert html =~ level_option.full_name
      assert html =~ level_option.level.name
      assert html =~ to_string(level_option.option.name)
    end

    test "updates level_option and returns to show", %{
      conn: conn,
      tenant: tenant,
      level_option: level_option
    } do
      {:ok, show_live, _html} = live(conn, ~p"/configurations/levels_options/#{level_option}")
      [subject_1, subject_2, subject_3] = generate_many(subject(tenant: tenant), 3)

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Manage Subjects")
               |> render_click()
               |> follow_redirect(
                 conn,
                 ~p"/configurations/levels_options/#{level_option}/manage_subjects"
               )

      assert render(form_live) =~ "Edit Level Options Subjects"

      invalid_attrs = %{
        selected_subjects: [],
        subjects: %{
          0 => %{coefficient: nil}
        }
      }

      attrs = %{
        selected_subjects: [subject_1.id, subject_2.id],
        subjects: %{
          0 => %{coefficient: 4},
          1 => %{coefficient: 3}
        }
      }

      assert form_live
             |> form("#level_option-form", level_option: invalid_attrs)
             |> render_change() =~ "is required"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#level_option-form", level_option: attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/configurations/levels_options/#{level_option}")

      html = render(show_live)
      assert html =~ "Subjects updated successfully"
      assert html =~ level_option.full_name
      assert html =~ subject_1.name
      assert html =~ to_string(4)
      assert html =~ subject_2.name
      assert html =~ to_string(3)
      refute html =~ subject_3.name
    end
  end
end
