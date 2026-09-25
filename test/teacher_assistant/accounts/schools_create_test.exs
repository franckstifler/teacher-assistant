defmodule TeacherAssistant.Accounts.SchoolsCreateTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Accounts.{SchoolProfile, SchoolMembership}
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.TeacherFixtures

  @attrs %{
    name: "Lycée Bilingue",
    school_type: :gbhs,
    subsystem: :bilingual,
    sector: :public,
    region: :centre,
    town: "Yaoundé"
  }

  test "creates workspace + unverified profile + head membership, with the creator as owner" do
    user = TeacherFixtures.user_fixture()
    user_scope = %TeacherAssistant.Scope{current_user: user}
    assert {:ok, %Workspace{} = school} = Organization.create_school(user_scope, @attrs)
    scope = school_scope(user, school)
    assert {:ok, profile} = Accounts.fetch_school_profile(scope)
    assert profile.verification_status == :unverified
    assert profile.owner_user_id == user.id
    assert profile.subsystem == :bilingual
    assert {:ok, membership} = Accounts.fetch_school_membership(scope, user)
    assert :head in membership.roles
  end

  test "create_school seeds the default bell schedule" do
    user = TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, @attrs)

    periods = TeacherAssistant.Attendance.list_periods(school_scope(user, school))
    assert periods != []
    assert Enum.any?(periods, &(&1.kind == :lesson))
  end

  test "setup_complete_school_fixture builds the year's calendar" do
    %{workspace: _school, year: year, scope: scope} =
      TeacherFixtures.setup_complete_school_fixture()

    assert length(Organization.list_sequences(scope, year)) == 6
  end

  test "is atomic: an invalid profile field leaves no workspace, profile or membership" do
    user = TeacherFixtures.user_fixture()
    before_ws = Workspace |> Ash.count!(authorize?: false)

    assert {:error, _} =
             Organization.create_school(
               %TeacherAssistant.Scope{current_user: user},
               Map.put(@attrs, :school_type, :bogus)
             )

    assert Workspace |> Ash.count!(authorize?: false) == before_ws

    assert SchoolProfile |> Ash.count!(authorize?: false) == 0
    assert SchoolMembership |> Ash.count!(authorize?: false) == 0
  end

  test "create_school defaults identity fields when omitted, for backward compatibility" do
    user = TeacherFixtures.user_fixture()

    assert {:ok, school} =
             Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{
               name: "Lycée Simple"
             })

    assert {:ok, profile} = Accounts.fetch_school_profile(school_scope(user, school))
    assert profile.school_type == :lycee
    assert profile.subsystem == :francophone
    assert profile.sector == :public
    assert profile.region == :centre
    assert profile.town == "—"
  end

  test "verify and reject transitions" do
    user = TeacherFixtures.user_fixture()
    op = TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, @attrs)

    scope = school_scope(user, school)
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    {:ok, verified} = Accounts.verify_school(profile, op.id, scope: scope)
    assert verified.verification_status == :verified
    {:ok, rejected} = Accounts.reject_school(verified, op.id, "doc manquant", scope: scope)
    assert rejected.verification_status == :rejected
    assert rejected.rejection_reason == "doc manquant"
  end

  test "editing a rejected school's profile re-opens it for verification" do
    user = TeacherFixtures.user_fixture()
    op = TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, @attrs)

    scope = school_scope(user, school)
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    {:ok, rejected} = Accounts.reject_school(profile, op.id, "doc manquant", scope: scope)
    assert rejected.verification_status == :rejected

    assert {:ok, updated} =
             Accounts.update_school_profile(rejected, %{short_name: "X"}, scope: scope)

    assert updated.verification_status == :unverified
    assert updated.rejection_reason == nil
    assert updated.verified_at == nil
    assert updated.verified_by_user_id == nil
    assert updated.short_name == "X"

    assert Enum.any?(Accounts.list_unverified_schools(scope), &(&1.id == updated.id))
  end

  test "editing a verified school's profile leaves it verified" do
    user = TeacherFixtures.user_fixture()
    op = TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, @attrs)

    scope = school_scope(user, school)
    {:ok, profile} = Accounts.fetch_school_profile(scope)
    {:ok, verified} = Accounts.verify_school(profile, op.id, scope: scope)
    assert verified.verification_status == :verified

    assert {:ok, updated} =
             Accounts.update_school_profile(verified, %{short_name: "Y"}, scope: scope)

    assert updated.verification_status == :verified
    assert updated.verified_at != nil
    assert updated.verified_by_user_id == op.id
    assert updated.short_name == "Y"
  end

  test "create_school seeds catalog, periods and head membership under the new tenant" do
    user = TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, @attrs)

    scope = school_scope(user, school)

    for {resource, list} <- [
          {TeacherAssistant.Academics.Subject, TeacherAssistant.Curriculum.list_subjects(scope)},
          {TeacherAssistant.Academics.Period, TeacherAssistant.Attendance.list_periods(scope)}
        ] do
      assert list != [], inspect(resource)
      assert Enum.all?(list, &(&1.workspace_id == school.id))
    end

    assert {:ok, %{workspace_id: wid}} = Accounts.fetch_school_membership(scope, user)
    assert wid == school.id
  end
end
