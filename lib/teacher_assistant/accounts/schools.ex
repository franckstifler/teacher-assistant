defmodule TeacherAssistant.Accounts.Schools do
  @moduledoc "School workspaces, memberships, and invitations (Phase 2 school layer)."
  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.{SchoolMembership, User}

  def create_school(%User{} = user, %{} = attrs) do
    with {:ok, school} <-
           Workspace
           |> Ash.Changeset.for_create(:create, %{name: attrs[:name] || attrs["name"], kind: :school})
           |> Ash.create(authorize?: false),
         {:ok, _membership} <-
           SchoolMembership
           |> Ash.Changeset.for_create(:create, %{
             workspace_id: school.id,
             user_id: user.id,
             roles: [:head]
           })
           |> Ash.create(authorize?: false) do
      {:ok, school}
    end
  end

  def list_workspaces_for(%User{} = user) do
    personal = Academics.ensure_personal_workspace!(user)

    schools =
      SchoolMembership
      |> Ash.Query.filter(user_id == ^user.id and active == true)
      |> Ash.Query.load(:workspace)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.workspace)

    [personal | schools]
  end

  def fetch_school_membership(%Workspace{id: ws_id}, %User{id: user_id}) do
    SchoolMembership
    |> Ash.Query.filter(workspace_id == ^ws_id and user_id == ^user_id and active == true)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_a_member}
      {:ok, m} -> {:ok, m}
      error -> error
    end
  end

  def list_members(%Workspace{id: ws_id}) do
    SchoolMembership
    |> Ash.Query.filter(workspace_id == ^ws_id and active == true)
    |> Ash.Query.load(:user)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  def update_member_roles(%SchoolMembership{} = m, roles) do
    if removing_last_head?(m, roles) do
      {:error, :last_head}
    else
      m |> Ash.Changeset.for_update(:update, %{roles: roles}) |> Ash.update(authorize?: false)
    end
  end

  def deactivate_member(%SchoolMembership{} = m) do
    if :head in m.roles and last_head?(m) do
      {:error, :last_head}
    else
      m |> Ash.Changeset.for_update(:update, %{active: false}) |> Ash.update(authorize?: false)
    end
  end

  defp removing_last_head?(%SchoolMembership{} = m, new_roles) do
    :head in m.roles and :head not in new_roles and last_head?(m)
  end

  defp last_head?(%SchoolMembership{workspace_id: ws_id, id: id}) do
    heads =
      SchoolMembership
      |> Ash.Query.filter(workspace_id == ^ws_id and active == true)
      |> Ash.read!(authorize?: false)
      |> Enum.filter(fn m -> :head in m.roles and m.id != id end)

    heads == []
  end
end
