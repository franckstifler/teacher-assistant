defmodule TeacherAssistantWeb.School.SettingsEyebrowsTest do
  @moduledoc "Every page of the « Paramètres » menu says so above its title."
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
      assert has_element?(view, "header p.ta-eyebrow", "Paramètres")
    end
  end
end
