defmodule TeacherAssistantWeb.School.SettingsProfileTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.{SchoolMembership, Schools}

  setup :register_and_log_in_user

  describe "with a school profile" do
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

  describe "without a school profile" do
    setup %{conn: conn, actor: user} do
      {:ok, school} =
        Workspace
        |> Ash.Changeset.for_create(:create, %{name: "Bare School", kind: :school})
        |> Ash.create(authorize?: false)

      {:ok, _membership} =
        SchoolMembership
        |> Ash.Changeset.for_create(:create, %{
          workspace_id: school.id,
          user_id: user.id,
          roles: [:head]
        })
        |> Ash.create(authorize?: false)

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:user_id, user.id)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      %{conn: conn, school: school}
    end

    test "an admin visiting settings does not crash and the profile form is absent", %{
      conn: conn
    } do
      assert {:ok, view, _html} = live(conn, ~p"/school/settings")
      refute has_element?(view, "#school-profile-form")
    end
  end
end
