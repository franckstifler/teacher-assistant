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

  @doc """
  Creates an active academic year for `workspace` and seeds its starter
  classes, so `TeacherAssistant.Scope.setup_complete?/1` is true for it.
  Requires `workspace` to already have a `SchoolProfile` (as
  `Organization.create_school/2` sets up) — `Seeding.seed_starter_classes/2`
  reads it to pick the class template.
  """
  def complete_school_setup!(workspace, attrs \\ %{}) do
    {:ok, year} =
      Organization.create_academic_year(workspace, %{
        name: attrs[:name] || "Année de référence",
        start_date: attrs[:start_date] || ~D[2025-09-08],
        end_date: attrs[:end_date] || ~D[2026-07-31],
        active: true
      })

    {:ok, _count} = TeacherAssistant.Academics.Seeding.seed_starter_classes(workspace, year)

    year
  end

  @doc """
  A school whose setup is already complete (active academic year + at least
  one class group), so it never hits the `:require_school_setup` gate.
  """
  def setup_complete_school_fixture(attrs \\ %{}) do
    %{workspace: ws, head_user: head} = school_fixture(attrs)
    year = complete_school_setup!(ws)
    %{workspace: ws, head_user: head, year: year}
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
