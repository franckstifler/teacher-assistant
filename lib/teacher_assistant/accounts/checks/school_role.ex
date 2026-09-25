defmodule TeacherAssistant.Accounts.Checks.SchoolRole do
  @moduledoc """
  Policy check: the actor holds an **active** membership in the subject's school
  whose roles intersect `SchoolRole.axis(any_of)`.

      authorize_if {TeacherAssistant.Accounts.Checks.SchoolRole, any_of: :admin}

  The school is the subject's tenant; for the two non-tenant school resources
  it comes from the record (`Workspace.id`, `SchoolProfile.workspace_id`). No
  actor, no resolvable school or no active membership → `false`. The
  membership is read fresh on every check, so a revoked member is refused on
  their next call, even inside an open LiveView.
  """
  use Ash.Policy.SimpleCheck

  alias TeacherAssistant.Academics.Workspace
  alias TeacherAssistant.Accounts.{SchoolMembership, SchoolProfile}
  alias TeacherAssistant.Accounts.SchoolRole, as: Roles

  @impl true
  def describe(opts), do: "actor holds a #{inspect(opts[:any_of])} role in the school"

  @impl true
  def match?(actor, %{subject: subject}, opts),
    do: holds?(actor, workspace_id(subject), Keyword.fetch!(opts, :any_of))

  def match?(_actor, _context, _opts), do: false

  @doc "Whether `user` holds a role of `axis` in the school `workspace_id` (fresh read)."
  def holds?(%{id: user_id}, workspace_id, axis) when is_binary(workspace_id) do
    case active_roles(user_id, workspace_id) do
      nil -> false
      roles -> axis == :member or Enum.any?(roles, &(&1 in Roles.axis(axis)))
    end
  end

  def holds?(_user, _workspace_id, _axis), do: false

  @doc "The school a policy subject (query, changeset or action input) belongs to."
  def workspace_id(%{resource: Workspace, data: %Workspace{id: id}}) when is_binary(id), do: id

  def workspace_id(%{resource: SchoolProfile, data: %SchoolProfile{workspace_id: id}})
      when is_binary(id),
      do: id

  def workspace_id(%{tenant: %{id: id}}), do: id
  def workspace_id(%{tenant: id}) when is_binary(id), do: id
  def workspace_id(_subject), do: nil

  # Check-internal read: `authorize?: false` because a policy check must not
  # recurse into the policies it is part of.
  defp active_roles(user_id, workspace_id) do
    SchoolMembership
    |> Ash.Query.for_read(:for_workspace_and_user, %{user_id: user_id})
    |> Ash.Query.set_tenant(workspace_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %SchoolMembership{roles: roles}} -> roles
      _ -> nil
    end
  end
end
