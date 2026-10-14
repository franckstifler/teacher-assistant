defmodule TeacherAssistantWeb.School.SettingsEyebrowsTest do
  @moduledoc "Every settings page leads back to the Paramètres hub (or one of its pages) above its title."
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  for path <-
        ~w(/school/settings/coefficients /school/settings/evaluations /school/settings/appreciations
           /school/settings/passage /school/settings/school-life /school/settings/bulletin
           /school/settings/holidays /school/settings/assignments /school/periods
           /school/settings/roles /school/settings/header) do
    test "#{path} is under « Paramètres »", %{conn: conn} do
      {:ok, view, _} = live(conn, unquote(path))
      # the `back_header` link back to the hub, or to a hub page (the header's parent)
      assert has_element?(view, "header a[href^='/school/settings']")
    end
  end
end
