defmodule TeacherAssistant.Accounts do
  use Ash.Domain,
    otp_app: :teacher_assistant

  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.{SchoolInvitation, SchoolMembership, SchoolProfile, User}
  alias TeacherAssistant.Accounts.User.Senders.SendSchoolInvitationEmail

  resources do
    resource TeacherAssistant.Accounts.Token
    resource User
    resource SchoolMembership

    resource SchoolInvitation do
      define :revoke_invitation, action: :revoke
    end

    resource SchoolProfile do
      define :update_school_profile, action: :update
      define :verify_school, action: :verify, args: [:verified_by_user_id]
      define :reject_school, action: :reject, args: [:verified_by_user_id, :rejection_reason]
    end
  end

  authorization do
    authorize :when_requested
  end

  def create_user(attrs) do
    User
    |> Ash.Changeset.for_create(:register_with_password, attrs)
    |> Ash.create(authorize?: false)
  end

  def get_user(id) when is_binary(id), do: Ash.get(User, id, authorize?: false)
  def get_user(_id), do: {:error, :not_found}

  def promote_to_admin(%User{} = user) do
    user |> Ash.Changeset.for_update(:promote_to_admin, %{}) |> Ash.update(authorize?: false)
  end

  def ensure_personal_workspace!(%TeacherAssistant.Accounts.User{} = user),
    do: TeacherAssistant.Organization.ensure_personal_workspace!(user)

  # --- School profiles -----------------------------------------------------

  def fetch_school_profile(%Workspace{id: ws_id}) do
    SchoolProfile
    |> Ash.Query.for_read(:for_workspace, %{workspace_id: ws_id})
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def list_unverified_schools do
    SchoolProfile |> Ash.Query.for_read(:unverified) |> Ash.read!()
  end

  # --- School memberships --------------------------------------------------

  def fetch_school_membership(%Workspace{id: ws_id}, %User{id: user_id}) do
    SchoolMembership
    |> Ash.Query.for_read(:for_workspace_and_user, %{workspace_id: ws_id, user_id: user_id})
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_a_member}
      {:ok, m} -> {:ok, m}
      error -> error
    end
  end

  def list_members(%Workspace{id: ws_id}) do
    SchoolMembership
    |> Ash.Query.for_read(:active_for_workspace, %{workspace_id: ws_id})
    |> Ash.read!()
  end

  def update_member_roles(%SchoolMembership{} = m, roles) do
    if removing_last_head?(m, roles) do
      {:error, :last_head}
    else
      m |> Ash.Changeset.for_update(:update, %{roles: roles}) |> Ash.update()
    end
  end

  def deactivate_member(%SchoolMembership{} = m) do
    if :head in m.roles and last_head?(m) do
      {:error, :last_head}
    else
      m |> Ash.Changeset.for_update(:deactivate, %{}) |> Ash.update()
    end
  end

  defp removing_last_head?(%SchoolMembership{} = m, new_roles) do
    :head in m.roles and :head not in new_roles and last_head?(m)
  end

  # TEMP: Task D1 replaces this with an `other_active_heads` aggregate + a
  # resource validation. Until then the "can't remove/deactivate the last
  # head" guard lives here so the callers keep returning `{:error, :last_head}`.
  defp last_head?(%SchoolMembership{workspace_id: ws_id, id: id}) do
    heads =
      %Workspace{id: ws_id}
      |> list_members()
      |> Enum.filter(fn m -> :head in m.roles and m.id != id end)

    heads == []
  end

  # --- School invitations --------------------------------------------------

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
        |> Ash.create()

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
    |> Ash.Query.for_read(:by_token, %{token: token})
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      {:ok, inv} -> {:ok, inv}
      error -> error
    end
  end

  def list_pending_invitations(%Workspace{id: ws_id}) do
    SchoolInvitation
    |> Ash.Query.for_read(:pending_for_workspace, %{workspace_id: ws_id})
    |> Ash.read!()
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
            |> Ash.create()

          {:ok, _} =
            inv
            |> Ash.Changeset.for_update(:update, %{status: :accepted})
            |> Ash.update()

          {:ok, inv.workspace}
      end
    else
      {:error, :not_found} -> {:error, :invalid}
      other -> other
    end
  end

  defp check_acceptable(%SchoolInvitation{status: :pending} = inv) do
    cond do
      inv.expires_at && DateTime.compare(DateTime.utc_now(), inv.expires_at) == :gt ->
        {:error, :expired}

      true ->
        :ok
    end
  end

  defp check_acceptable(_), do: {:error, :invalid}

  defp check_email(%SchoolInvitation{email: email}, %User{email: user_email}) do
    if to_string(email) == to_string(user_email), do: :ok, else: {:error, :email_mismatch}
  end

  defp active_member_email?(%Workspace{} = school, email) do
    school
    |> list_members()
    |> Enum.any?(fn m -> to_string(m.user.email) == to_string(email) end)
  end

  defp gen_token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
