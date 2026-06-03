defmodule TeacherAssistant.Accounts.Workspaces do
  @moduledoc """
  Resolves the selected school/personal workspace for authenticated users.
  """

  require Ash.Query

  alias TeacherAssistant.Accounts.UserSchool
  alias TeacherAssistant.Accounts.SchoolInvitation
  alias TeacherAssistant.Academics.AcademicYear
  alias TeacherAssistant.Academics.School
  alias TeacherAssistant.Scope

  def ensure_personal_workspace!(nil), do: nil

  def ensure_personal_workspace!(user) do
    case personal_workspace(user) do
      {:ok, %School{} = workspace} ->
        ensure_membership!(user, workspace.id, :teacher)
        workspace

      _ ->
        create_personal_workspace!(user)
    end
  end

  def membership_for!(user, workspace_id) do
    case membership_for(user, workspace_id) do
      {:ok, membership} -> membership
      {:error, reason} -> raise "Workspace membership not found: #{inspect(reason)}"
    end
  end

  def membership_for(nil, _workspace_id), do: {:error, :no_user}
  def membership_for(_user, nil), do: {:error, :workspace_required}

  def membership_for(user, workspace_id) do
    UserSchool
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.read_one(tenant: workspace_id, authorize?: false)
    |> case do
      {:ok, %UserSchool{} = membership} -> {:ok, membership}
      {:ok, nil} -> {:error, :not_a_member}
      {:error, error} -> {:error, error}
    end
  end

  def scope_for!(user, workspace_id) do
    case scope_for(user, workspace_id) do
      {:ok, scope} -> scope
      {:error, reason} -> raise "Workspace scope could not be resolved: #{inspect(reason)}"
    end
  end

  def scope_for(nil, _workspace_id), do: {:error, :no_user}
  def scope_for(_user, nil), do: {:error, :workspace_required}

  def scope_for(user, workspace_id) do
    with {:ok, workspace} <- load_workspace(workspace_id),
         {:ok, membership} <- membership_for(user, workspace.id) do
      role = membership.role || :teacher
      actor = %{user | role: role}

      {:ok,
       %Scope{
         current_user: actor,
         current_tenant: workspace,
         current_workspace: workspace,
         current_workspace_type: workspace.workspace_type || :school,
         current_role: role,
         current_academic_year: active_academic_year(workspace, actor)
       }}
    end
  end

  def list_workspaces(user) do
    ensure_personal_workspace!(user)

    School
    |> Ash.read!(authorize?: false)
    |> Enum.filter(fn workspace ->
      match?({:ok, %UserSchool{}}, membership_for(user, workspace.id))
    end)
    |> Enum.sort_by(&{workspace_sort(&1), String.downcase(&1.name || "")})
  end

  def invite_user!(%{school: %School{} = school, inviter: inviter, email: email, role: role}) do
    ensure_inviter_can_manage_members!(inviter, school.id)

    SchoolInvitation
    |> Ash.Changeset.for_create(
      :create,
      %{
        email: email,
        role: role,
        token: invitation_token(),
        status: :pending,
        school_id: school.id,
        invited_by_user_id: inviter.id
      }
    )
    |> Ash.create!(authorize?: false)
  end

  def accept_invitation!(user, token) when is_binary(token) do
    invitation =
      SchoolInvitation
      |> Ash.Query.filter(token == ^token and status == :pending)
      |> Ash.read_one!(authorize?: false)

    cond do
      is_nil(invitation) ->
        raise "Invitation could not be accepted"

      String.downcase(to_string(invitation.email)) != String.downcase(to_string(user.email)) ->
        raise "Invitation could not be accepted"

      true ->
        ensure_membership!(user, invitation.school_id, invitation.role)

        invitation
        |> Ash.Changeset.for_update(:accept, %{
          status: :accepted,
          accepted_by_user_id: user.id,
          accepted_at: DateTime.utc_now()
        })
        |> Ash.update!(authorize?: false)
    end
  end

  defp personal_workspace(user) do
    School
    |> Ash.Query.filter(workspace_type == :personal_teacher and owner_user_id == ^user.id)
    |> Ash.read_one(authorize?: false)
  end

  defp create_personal_workspace!(user) do
    workspace =
      School
      |> Ash.Changeset.for_create(:create, %{
        name: personal_workspace_name(user),
        abbreviation: "Personal",
        workspace_type: :personal_teacher,
        owner_user_id: user.id,
        description: "Private pedagogic workspace"
      })
      |> Ash.create!(authorize?: false)

    ensure_membership!(user, workspace.id, :teacher)
    workspace
  end

  defp ensure_membership!(user, workspace_id, role) do
    case membership_for(user, workspace_id) do
      {:ok, membership} ->
        membership

      {:error, :not_a_member} ->
        UserSchool
        |> Ash.Changeset.for_create(:create, %{user_id: user.id, role: role},
          tenant: workspace_id
        )
        |> Ash.create!(authorize?: false)
    end
  end

  defp ensure_inviter_can_manage_members!(inviter, school_id) do
    case membership_for(inviter, school_id) do
      {:ok, %{role: role}} when role in [:admin, :principal, :vice_principal] ->
        :ok

      _ ->
        raise "User cannot invite members to this school"
    end
  end

  defp load_workspace(workspace_id) do
    case Ash.get(School, workspace_id, authorize?: false) do
      {:ok, %School{} = workspace} -> {:ok, workspace}
      {:ok, nil} -> {:error, :workspace_not_found}
      {:error, error} -> {:error, error}
    end
  end

  defp active_academic_year(workspace, actor) do
    AcademicYear
    |> Ash.Query.filter(active == true)
    |> Ash.Query.sort(start_date: :desc)
    |> Ash.read_one(tenant: workspace, actor: actor)
    |> case do
      {:ok, year} -> year
      _ -> nil
    end
  end

  defp personal_workspace_name(user) do
    email = user.email |> to_string() |> String.split("@") |> List.first()
    "#{email}'s teacher workspace"
  end

  defp workspace_sort(%{workspace_type: :personal_teacher}), do: 0
  defp workspace_sort(_workspace), do: 1

  defp invitation_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
