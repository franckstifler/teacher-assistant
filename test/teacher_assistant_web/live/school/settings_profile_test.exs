defmodule TeacherAssistantWeb.School.SettingsProfileTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.{SchoolMembership}
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  describe "with a school profile" do
    setup %{conn: conn, actor: user} do
      {:ok, school} = Organization.create_school(user, %{name: "Ancien Nom"})
      TeacherAssistant.TeacherFixtures.complete_school_setup!(school_scope(user, school))
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

      {:ok, p} = Accounts.fetch_school_profile(school)
      assert p.short_name == "GBHS"
      assert p.head_name == "M. Ndenge"
    end
  end

  describe "without a school profile" do
    setup %{conn: conn, actor: user} do
      {:ok, school} =
        Workspace
        |> Ash.Changeset.for_create(:create, %{name: "Bare School"})
        |> Ash.create(authorize?: false)

      {:ok, _membership} =
        SchoolMembership
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          roles: [:head]
        })
        |> Ash.Changeset.set_tenant(school.id)
        |> Ash.create(authorize?: false)

      # This workspace has no SchoolProfile row (that's the point of this
      # describe block), so `TeacherFixtures.complete_school_setup!/1` can't
      # be used (it seeds classes from the profile's school-type template).
      # Create the year + class directly to satisfy the setup-complete gate.
      {:ok, year} =
        Organization.create_academic_year(school, %{
          name: "2025-2026",
          start_date: ~D[2025-09-08],
          end_date: ~D[2026-07-31],
          active: true
        })

      {:ok, _cg} = Enrollment.create_class_group(school, year, %{label: "6e A", level: "6ème"})

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
