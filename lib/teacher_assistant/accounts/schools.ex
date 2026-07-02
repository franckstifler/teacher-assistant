defmodule TeacherAssistant.Accounts.Schools do
  @moduledoc "School workspaces, memberships, and invitations (Phase 2 school layer)."
  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.{SchoolInvitation, SchoolMembership, User}
  alias TeacherAssistant.Accounts.User.Senders.SendSchoolInvitationEmail

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

  def invite_member(%Workspace{} = school, %User{} = inviter, %{} = attrs) do
    email = attrs[:email] || attrs["email"]
    roles = attrs[:roles] || attrs["roles"] || [:teacher]

    if active_member_email?(school, email) do
      {:error, :already_member}
    else
      {:ok, invitation} =
        SchoolInvitation
        |> Ash.Changeset.for_create(:create, %{
          workspace_id: school.id,
          email: email,
          roles: roles,
          invited_by_user_id: inviter.id,
          token: gen_token(),
          expires_at: DateTime.add(DateTime.utc_now(), 14, :day) |> DateTime.truncate(:second)
        })
        |> Ash.create(authorize?: false)

      SendSchoolInvitationEmail.send(
        invitation.email,
        school.name,
        invitation.token
      )

      {:ok, invitation}
    end
  end

  def fetch_invitation_by_token(token) do
    SchoolInvitation
    |> Ash.Query.filter(token == ^token)
    |> Ash.Query.load(:workspace)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      {:ok, inv} -> {:ok, inv}
      error -> error
    end
  end

  def list_pending_invitations(%Workspace{id: ws_id}) do
    SchoolInvitation
    |> Ash.Query.filter(workspace_id == ^ws_id and status == :pending)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  def revoke_invitation(%SchoolInvitation{} = inv) do
    inv |> Ash.Changeset.for_update(:update, %{status: :revoked}) |> Ash.update(authorize?: false)
  end

  def accept_invitation(token, %User{} = user) do
    with {:ok, inv} <- fetch_invitation_by_token(token),
         :ok <- check_acceptable(inv),
         :ok <- check_email(inv, user) do
      case fetch_school_membership(inv.workspace, user) do
        {:ok, _already} ->
          {:ok, inv.workspace}

        {:error, :not_a_member} ->
          {:ok, _m} =
            SchoolMembership
            |> Ash.Changeset.for_create(:create, %{
              workspace_id: inv.workspace_id,
              user_id: user.id,
              roles: inv.roles
            })
            |> Ash.create(authorize?: false)

          {:ok, _} = inv |> Ash.Changeset.for_update(:update, %{status: :accepted}) |> Ash.update(authorize?: false)
          {:ok, inv.workspace}
      end
    else
      {:error, :not_found} -> {:error, :invalid}
      other -> other
    end
  end

  defp check_acceptable(%SchoolInvitation{status: :pending} = inv) do
    cond do
      inv.expires_at && DateTime.compare(DateTime.utc_now(), inv.expires_at) == :gt -> {:error, :expired}
      true -> :ok
    end
  end

  defp check_acceptable(_), do: {:error, :invalid}

  defp check_email(%SchoolInvitation{email: email}, %User{email: user_email}) do
    if to_string(email) == to_string(user_email), do: :ok, else: {:error, :email_mismatch}
  end

  defp active_member_email?(%Workspace{id: ws_id}, email) do
    SchoolMembership
    |> Ash.Query.filter(workspace_id == ^ws_id and active == true)
    |> Ash.Query.load(:user)
    |> Ash.read!(authorize?: false)
    |> Enum.any?(fn m -> to_string(m.user.email) == to_string(email) end)
  end

  defp gen_token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
