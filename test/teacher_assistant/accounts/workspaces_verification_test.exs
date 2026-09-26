defmodule TeacherAssistant.Accounts.WorkspacesVerificationTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.{Workspaces}
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Scope
  alias TeacherAssistant.TeacherFixtures

  @attrs %{
    name: "Lycée V",
    school_type: :lycee,
    subsystem: :francophone,
    sector: :public,
    region: :centre,
    town: "Yaoundé"
  }

  test "school scope reflects verification status" do
    user = TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, @attrs)

    {:ok, scope} = Workspaces.scope_for(user, school.id)
    assert scope.school_verification_status == :unverified
    refute Scope.school_verified?(scope)

    :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)

    {:ok, scope2} = Workspaces.scope_for(user, scope.current_workspace.id)
    assert scope2.school_verification_status == :verified
    assert Scope.school_verified?(scope2)
  end
end
