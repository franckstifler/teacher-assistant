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
    assert {:ok, %Workspace{} = school} = Organization.create_school(user, @attrs)
    assert {:ok, profile} = Accounts.fetch_school_profile(school)
    assert profile.verification_status == :unverified
    assert profile.owner_user_id == user.id
    assert profile.subsystem == :bilingual
    assert {:ok, membership} = Accounts.fetch_school_membership(school, user)
    assert :head in membership.roles
  end

  test "create_school seeds the default bell schedule" do
    user = TeacherFixtures.user_fixture()
    {:ok, school} = Organization.create_school(user, @attrs)
    periods = TeacherAssistant.Attendance.list_periods(school)
    assert periods != []
    assert Enum.any?(periods, &(&1.kind == :lesson))
  end

  test "setup_complete_school_fixture builds the year's calendar" do
    %{workspace: _school, year: year} = TeacherFixtures.setup_complete_school_fixture()
    assert length(Organization.list_sequences(year)) == 6
  end

  test "is atomic: an invalid profile field leaves no workspace, profile or membership" do
    user = TeacherFixtures.user_fixture()
    before_ws = Workspace |> Ash.count!(authorize?: false)
    assert {:error, _} = Organization.create_school(user, Map.put(@attrs, :school_type, :bogus))

    assert Workspace |> Ash.count!(authorize?: false) == before_ws

    assert SchoolProfile |> Ash.count!(authorize?: false) == 0
    assert SchoolMembership |> Ash.count!(authorize?: false) == 0
  end

  test "create_school defaults identity fields when omitted, for backward compatibility" do
    user = TeacherFixtures.user_fixture()
    assert {:ok, school} = Organization.create_school(user, %{name: "Lycée Simple"})
    assert {:ok, profile} = Accounts.fetch_school_profile(school)
    assert profile.school_type == :lycee
    assert profile.subsystem == :francophone
    assert profile.sector == :public
    assert profile.region == :centre
    assert profile.town == "—"
  end

  test "verify and reject transitions" do
    user = TeacherFixtures.user_fixture()
    op = TeacherFixtures.user_fixture()
    {:ok, school} = Organization.create_school(user, @attrs)
    {:ok, profile} = Accounts.fetch_school_profile(school)
    {:ok, verified} = Accounts.verify_school(profile, op.id)
    assert verified.verification_status == :verified
    {:ok, rejected} = Accounts.reject_school(verified, op.id, "doc manquant")
    assert rejected.verification_status == :rejected
    assert rejected.rejection_reason == "doc manquant"
  end

  test "editing a rejected school's profile re-opens it for verification" do
    user = TeacherFixtures.user_fixture()
    op = TeacherFixtures.user_fixture()
    {:ok, school} = Organization.create_school(user, @attrs)
    {:ok, profile} = Accounts.fetch_school_profile(school)
    {:ok, rejected} = Accounts.reject_school(profile, op.id, "doc manquant")
    assert rejected.verification_status == :rejected

    assert {:ok, updated} = Accounts.update_school_profile(rejected, %{short_name: "X"})
    assert updated.verification_status == :unverified
    assert updated.rejection_reason == nil
    assert updated.verified_at == nil
    assert updated.verified_by_user_id == nil
    assert updated.short_name == "X"

    assert Enum.any?(Accounts.list_unverified_schools(), &(&1.id == updated.id))
  end

  test "editing a verified school's profile leaves it verified" do
    user = TeacherFixtures.user_fixture()
    op = TeacherFixtures.user_fixture()
    {:ok, school} = Organization.create_school(user, @attrs)
    {:ok, profile} = Accounts.fetch_school_profile(school)
    {:ok, verified} = Accounts.verify_school(profile, op.id)
    assert verified.verification_status == :verified

    assert {:ok, updated} = Accounts.update_school_profile(verified, %{short_name: "Y"})
    assert updated.verification_status == :verified
    assert updated.verified_at != nil
    assert updated.verified_by_user_id == op.id
    assert updated.short_name == "Y"
  end

  test "create_school seeds catalog, periods and head membership under the new tenant" do
    user = TeacherFixtures.user_fixture()
    {:ok, school} = Organization.create_school(user, @attrs)

    for {resource, list} <- [
          {TeacherAssistant.Academics.Subject, TeacherAssistant.Curriculum.list_subjects(school)},
          {TeacherAssistant.Academics.Period, TeacherAssistant.Attendance.list_periods(school)}
        ] do
      assert list != [], inspect(resource)
      assert Enum.all?(list, &(&1.workspace_id == school.id))
    end

    assert {:ok, %{workspace_id: wid}} = Accounts.fetch_school_membership(school, user)
    assert wid == school.id
  end
end
