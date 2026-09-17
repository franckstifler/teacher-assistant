defmodule TeacherAssistant.Accounts.SchoolsCreateTest do
  use TeacherAssistant.DataCase, async: true
  require Ash.Query
  alias TeacherAssistant.Accounts.{Schools, SchoolProfile, SchoolMembership}
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
    assert {:ok, %Workspace{} = school} = Schools.create_school(user, @attrs)
    assert {:ok, profile} = Schools.fetch_school_profile(school)
    assert profile.verification_status == :unverified
    assert profile.owner_user_id == user.id
    assert profile.subsystem == :bilingual
    assert {:ok, membership} = Schools.fetch_school_membership(school, user)
    assert :head in membership.roles
  end

  test "is atomic: an invalid profile field leaves no workspace, profile or membership" do
    user = TeacherFixtures.user_fixture()
    before_ws = Workspace |> Ash.Query.filter(kind == :school) |> Ash.count!(authorize?: false)
    assert {:error, _} = Schools.create_school(user, Map.put(@attrs, :school_type, :bogus))

    assert Workspace |> Ash.Query.filter(kind == :school) |> Ash.count!(authorize?: false) ==
             before_ws

    assert SchoolProfile |> Ash.count!(authorize?: false) == 0
    assert SchoolMembership |> Ash.count!(authorize?: false) == 0
  end

  test "create_school defaults identity fields when omitted, for backward compatibility" do
    user = TeacherFixtures.user_fixture()
    assert {:ok, school} = Schools.create_school(user, %{name: "Lycée Simple"})
    assert {:ok, profile} = Schools.fetch_school_profile(school)
    assert profile.school_type == :lycee
    assert profile.subsystem == :francophone
    assert profile.sector == :public
    assert profile.region == :centre
    assert profile.town == "—"
  end

  test "verify and reject transitions" do
    user = TeacherFixtures.user_fixture()
    op = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(user, @attrs)
    {:ok, profile} = Schools.fetch_school_profile(school)
    {:ok, verified} = Schools.verify_school(profile, op.id)
    assert verified.verification_status == :verified
    {:ok, rejected} = Schools.reject_school(verified, op.id, "doc manquant")
    assert rejected.verification_status == :rejected
    assert rejected.rejection_reason == "doc manquant"
  end

  test "editing a rejected school's profile re-opens it for verification" do
    user = TeacherFixtures.user_fixture()
    op = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(user, @attrs)
    {:ok, profile} = Schools.fetch_school_profile(school)
    {:ok, rejected} = Schools.reject_school(profile, op.id, "doc manquant")
    assert rejected.verification_status == :rejected

    assert {:ok, updated} = Schools.update_school_profile(rejected, %{short_name: "X"})
    assert updated.verification_status == :unverified
    assert updated.rejection_reason == nil
    assert updated.verified_at == nil
    assert updated.verified_by_user_id == nil
    assert updated.short_name == "X"

    assert Enum.any?(Schools.list_unverified_schools(), &(&1.id == updated.id))
  end

  test "editing a verified school's profile leaves it verified" do
    user = TeacherFixtures.user_fixture()
    op = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(user, @attrs)
    {:ok, profile} = Schools.fetch_school_profile(school)
    {:ok, verified} = Schools.verify_school(profile, op.id)
    assert verified.verification_status == :verified

    assert {:ok, updated} = Schools.update_school_profile(verified, %{short_name: "Y"})
    assert updated.verification_status == :verified
    assert updated.verified_at != nil
    assert updated.verified_by_user_id == op.id
    assert updated.short_name == "Y"
  end
end
