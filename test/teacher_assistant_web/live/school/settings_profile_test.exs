defmodule TeacherAssistantWeb.School.SettingsProfileTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Ancien Nom"})
    conn = get(conn, ~p"/workspaces/select/#{school.id}")
    %{conn: conn, school: school}
  end

  test "an admin edits the full school profile", %{conn: conn, school: school} do
    {:ok, view, _} = live(conn, ~p"/school/settings")

    view
    |> form("#school-profile-form", %{
      "profile" => %{
        "short_name" => "GBHS",
        "head_name" => "M. Ndenge",
        "phone" => "+237 6...",
        "motto" => "Rigueur",
        "registration_number" => "AR/2019/001",
        "department" => "Mfoundi",
        "address" => "BP 100"
      }
    })
    |> render_submit()

    {:ok, p} = Schools.fetch_school_profile(school)
    assert p.short_name == "GBHS"
    assert p.head_name == "M. Ndenge"
  end
end
