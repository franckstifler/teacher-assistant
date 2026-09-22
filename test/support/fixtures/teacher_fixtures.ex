defmodule TeacherAssistant.TeacherFixtures do
  alias TeacherAssistant.{Accounts, Organization}

  def user_fixture(attrs \\ %{}) do
    email = Map.get(attrs, :email, "teacher-#{System.unique_integer([:positive])}@example.com")

    {:ok, user} =
      Accounts.create_user(%{
        email: email,
        password: Map.get(attrs, :password, "password1234"),
        password_confirmation: Map.get(attrs, :password_confirmation, "password1234")
      })

    user
  end

  def workspace_fixture(user \\ user_fixture()), do: Organization.ensure_personal_workspace!(user)

  def admin_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, admin} = Accounts.promote_to_admin(user)
    admin
  end

  def school_fixture(attrs \\ %{}) do
    user = attrs[:head_user] || user_fixture()
    name = attrs[:name] || "Lycée #{System.unique_integer([:positive])}"
    {:ok, workspace} = Organization.create_school(user, %{name: name})
    %{workspace: workspace, head_user: user}
  end

  def membership_fixture(workspace, attrs \\ %{}) do
    user = attrs[:user] || user_fixture()
    roles = attrs[:roles] || [:teacher]

    {:ok, m} =
      Accounts.SchoolMembership
      |> Ash.Changeset.for_create(:create, %{
        workspace_id: workspace.id,
        user_id: user.id,
        roles: roles,
        status: attrs[:status],
        active: true
      })
      |> Ash.create(authorize?: false)

    m
  end
end
