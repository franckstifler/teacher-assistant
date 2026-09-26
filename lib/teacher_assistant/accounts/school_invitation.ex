defmodule TeacherAssistant.Accounts.SchoolInvitation do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  alias TeacherAssistant.Accounts.{Checks, SchoolMembership}

  postgres do
    table "school_invitations"
    repo TeacherAssistant.Repo

    references do
      reference :workspace, on_delete: :delete, index?: true
      reference :invited_by_user, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :email,
        :roles,
        :invited_by_user_id,
        :status,
        :membership_status,
        :token,
        :expires_at
      ],
      update: [:status]
    ]

    # Global read (no tenant): an invitation must be findable by its token
    # before a tenant is chosen (the accept flow).
    read :by_token do
      argument :token, :string, allow_nil?: false
      get? true
      filter expr(token == ^arg(:token))
    end

    # Tenant scoping (attribute multitenancy) already restricts this to the
    # given workspace; no `workspace_id` argument is needed any more. This
    # resource is `global? true` (`:by_token` needs that), so nothing stops a
    # missing tenant from silently reading pending invitations across every
    # workspace — `Tenancy.require_tenant/1` rejects it instead (mirrors
    # `SchoolMembership.:active_for_workspace`).
    read :pending_for_workspace do
      filter expr(status == :pending)
      prepare build(sort: [inserted_at: :asc])

      prepare fn query, _context ->
        Ash.Query.before_action(query, &TeacherAssistant.Tenancy.require_tenant/1)
      end
    end

    update :revoke do
      change set_attribute(:status, :revoked)
    end

    # Accepting an invitation: in one transaction, create (or reactivate) the
    # invitee's membership and mark the invitation accepted.
    update :accept do
      accept []
      require_atomic? false

      validate attribute_equals(:status, :pending), message: "is no longer pending"

      validate fn changeset, context ->
        inv = changeset.data

        cond do
          inv.expires_at && DateTime.compare(DateTime.utc_now(), inv.expires_at) == :gt ->
            {:error, field: :expires_at, message: "has expired"}

          to_string(inv.email) != to_string(context.actor && context.actor.email) ->
            {:error, field: :email, message: "does not match the signed-in user"}

          true ->
            :ok
        end
      end

      change set_attribute(:status, :accepted)

      change after_action(fn _changeset, inv, context ->
               with :ok <- ensure_membership(inv, context.actor) do
                 {:ok, inv}
               end
             end)
    end
  end

  policies do
    # The token is the credential: the accept page works signed-out.
    policy action(:by_token) do
      authorize_if always()
    end

    policy action([:read, :pending_for_workspace]) do
      authorize_if {Checks.SchoolRole, any_of: :head}
    end

    policy action(:accept) do
      authorize_if expr(email == ^actor(:email))
    end

    policy action([:create, :revoke, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :head}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
    global? true
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :email, :ci_string, allow_nil?: false, public?: true

    attribute :roles, {:array, TeacherAssistant.Accounts.SchoolRole},
      allow_nil?: false,
      public?: true

    attribute :status, TeacherAssistant.Accounts.InvitationStatus,
      allow_nil?: false,
      default: :pending,
      public?: true

    attribute :membership_status, TeacherAssistant.Accounts.MembershipStatus,
      allow_nil?: true,
      public?: true

    attribute :token, :string, allow_nil?: false, public?: true
    attribute :expires_at, :utc_datetime, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :invited_by_user, TeacherAssistant.Accounts.User do
      source_attribute :invited_by_user_id
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :unique_token, [:token], all_tenants?: true
  end

  # Bootstrap write (spec §4.1 case 2): the invitee is not a member until this
  # transaction commits, so no school policy could admit these reads/writes.
  defp ensure_membership(inv, user) do
    SchoolMembership
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.read_one(tenant: inv.workspace_id, authorize?: false)
    |> case do
      {:ok, %SchoolMembership{active: true}} ->
        :ok

      {:ok, %SchoolMembership{} = m} ->
        m
        |> Ash.Changeset.for_update(:update, %{
          active: true,
          roles: inv.roles,
          status: inv.membership_status
        })
        |> Ash.update(tenant: inv.workspace_id, authorize?: false)
        |> ok()

      {:ok, nil} ->
        SchoolMembership
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          roles: inv.roles,
          status: inv.membership_status
        })
        |> Ash.create(tenant: inv.workspace_id, authorize?: false)
        |> ok()

      {:error, error} ->
        {:error, error}
    end
  end

  defp ok({:ok, _}), do: :ok
  defp ok({:error, error}), do: {:error, error}
end
