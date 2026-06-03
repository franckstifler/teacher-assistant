defmodule TeacherAssistantWeb.SchoolInvitationLiveTest do
  use TeacherAssistantWeb.ConnCase

  import Phoenix.LiveViewTest

  alias TeacherAssistant.Accounts.SchoolInvitation
  require Ash.Query

  describe "school invitations" do
    setup [:register_and_log_in_user]

    test "admin invites a teacher by email", %{conn: conn, tenant: school} do
      {:ok, view, _html} = live(conn, ~p"/configurations/invitations")

      assert has_element?(view, "#school-invitation-form")

      view
      |> form("#school-invitation-form",
        invitation: %{email: "new.teacher@example.com", role: "teacher"}
      )
      |> render_submit()

      assert has_element?(view, "#school-invitations")

      invitation =
        SchoolInvitation
        |> Ash.Query.filter(email == "new.teacher@example.com")
        |> Ash.read_one!(authorize?: false)

      assert invitation.school_id == school.id
      assert invitation.status == :pending
      assert invitation.role == :teacher
    end
  end
end
