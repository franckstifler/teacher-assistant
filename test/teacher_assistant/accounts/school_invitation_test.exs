defmodule TeacherAssistant.Accounts.SchoolInvitationTest do
  use TeacherAssistant.DataCase

  import TeacherAssistant.AcademicFixtures

  alias TeacherAssistant.Accounts.Workspaces

  describe "school invitations" do
    test "admin invites and an existing user accepts into the school context" do
      school = generate(school())
      admin = generate(user_without_school(role: :admin))
      teacher = generate(user_without_school(role: :teacher, email: "teacher@example.com"))
      generate(user_school(tenant: school, user_id: admin.id, role: :admin))

      invite =
        Workspaces.invite_user!(%{
          school: school,
          inviter: admin,
          email: "teacher@example.com",
          role: :teacher
        })

      assert invite.status == :pending
      assert is_binary(invite.token)

      accepted = Workspaces.accept_invitation!(teacher, invite.token)

      assert accepted.status == :accepted
      assert %{role: :teacher} = Workspaces.membership_for!(teacher, school.id)
    end

    test "a user cannot accept an invitation sent to another email" do
      school = generate(school())
      admin = generate(user_without_school(role: :admin))
      wrong_user = generate(user_without_school(role: :teacher, email: "other@example.com"))
      generate(user_school(tenant: school, user_id: admin.id, role: :admin))

      invite =
        Workspaces.invite_user!(%{
          school: school,
          inviter: admin,
          email: "teacher@example.com",
          role: :teacher
        })

      assert_raise RuntimeError, ~r/Invitation could not be accepted/, fn ->
        Workspaces.accept_invitation!(wrong_user, invite.token)
      end
    end
  end
end
