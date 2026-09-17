defmodule TeacherAssistant.Accounts.WorkspacesVerificationTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.{Schools, Workspaces}
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
    {:ok, school} = Schools.create_school(user, @attrs)

    {:ok, scope} = Workspaces.scope_for(user, school.id)
    assert scope.school_verification_status == :unverified
    refute Scope.school_verified?(scope)

    {:ok, profile} = Schools.fetch_school_profile(school)
    {:ok, _} = Schools.verify_school(profile, user.id)

    {:ok, scope2} = Workspaces.scope_for(user, school.id)
    assert scope2.school_verification_status == :verified
    assert Scope.school_verified?(scope2)
  end

  test "personal scope has no verification" do
    user = TeacherFixtures.user_fixture()
    ws = TeacherAssistant.Academics.ensure_personal_workspace!(user)
    {:ok, scope} = Workspaces.scope_for(user, ws.id)
    assert scope.school_verification_status == nil
    refute Scope.school_verified?(scope)
  end
end
