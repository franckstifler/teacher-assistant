defmodule TeacherAssistantWeb.Onboarding.CreateSchoolLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.Academics.Workspace
  require Ash.Query

  setup :register_and_log_in_user

  test "creates an unverified school and switches into it", %{conn: conn, actor: user} do
    {:ok, view, _} = live(conn, ~p"/schools/new")

    assert {:error, {:redirect, %{to: to}}} =
             view
             |> form("#create-school-form", %{
               school: %{
                 name: "Collège Vogt",
                 school_type: "ces_ceg",
                 subsystem: "francophone",
                 sector: "private_confessional",
                 region: "centre",
                 town: "Yaoundé"
               }
             })
             |> render_submit()

    assert to =~ "/workspaces/select/"

    school =
      Workspace |> Ash.Query.filter(name == "Collège Vogt") |> Ash.read_one!(authorize?: false)

    {:ok, profile} = Schools.fetch_school_profile(school)
    assert profile.verification_status == :unverified
    assert profile.owner_user_id == user.id
  end
end
