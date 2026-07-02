defmodule TeacherAssistant.Accounts.SchoolResourcesTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.{SchoolMembership, SchoolInvitation, SchoolRoles}
  alias TeacherAssistant.TeacherFixtures

  setup do
    user = TeacherFixtures.user_fixture()

    {:ok, school} =
      Workspace
      |> Ash.Changeset.for_create(:create, %{name: "Lycée de Test", kind: :school})
      |> Ash.create(authorize?: false)

    %{user: user, school: school}
  end

  test "a membership persists with multiple roles", %{user: user, school: school} do
    {:ok, m} =
      SchoolMembership
      |> Ash.Changeset.for_create(:create, %{
        workspace_id: school.id,
        user_id: user.id,
        roles: [:head, :teacher],
        status: :titulaire
      })
      |> Ash.create(authorize?: false)

    assert m.roles == [:head, :teacher]
    assert m.active == true
  end

  test "membership is unique per (school, user)", %{user: user, school: school} do
    attrs = %{workspace_id: school.id, user_id: user.id, roles: [:teacher]}
    {:ok, _} = SchoolMembership |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)

    assert {:error, _} =
             SchoolMembership |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  test "an invitation defaults to pending and enforces a unique token", %{school: school} do
    attrs = %{workspace_id: school.id, email: "t@example.com", roles: [:teacher], token: "tok-1"}
    {:ok, inv} = SchoolInvitation |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
    assert inv.status == :pending

    assert {:error, _} =
             SchoolInvitation
             |> Ash.Changeset.for_create(:create, %{attrs | email: "u@example.com"})
             |> Ash.create(authorize?: false)
  end

  test "role labels are bilingual-ready", do: assert SchoolRoles.label(:head) =~ "Chef"
end
