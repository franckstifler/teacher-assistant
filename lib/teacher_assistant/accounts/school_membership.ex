defmodule TeacherAssistant.Accounts.SchoolMembership do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "school_memberships"
    repo TeacherAssistant.Repo

    custom_indexes do
      # `:active_for_user` is a GLOBAL read (no tenant) filtering on `user_id`
      # alone — the tenancy migration replaced the plain `user_id` index with
      # a `(workspace_id, user_id)` one, which can't serve a tenant-less scan.
      # `all_tenants?: true` opts this one index out of the automatic
      # `workspace_id` prefix attribute multitenancy otherwise adds to every
      # custom index, so it stays a genuinely plain, leading `user_id` index.
      index [:user_id], all_tenants?: true
    end

    references do
      reference :workspace, on_delete: :delete, index?: true
      reference :user, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:user_id, :roles, :status, :active],
      update: [:roles, :status, :active]
    ]

    # Tenant scoping (attribute multitenancy) already restricts this to the
    # given workspace; no `workspace_id` argument is needed any more.
    #
    # The resource is `global? true` (`:active_for_user` needs that), so Ash
    # lets any of its actions run without a tenant — a per-action
    # `multitenancy :enforce` is a no-op on a global resource. Without a
    # tenant this filter would run unscoped across every workspace, so
    # `Tenancy.require_tenant/1` rejects a missing tenant first.
    read :active_for_workspace do
      filter expr(active == true)
      prepare build(load: [:user], sort: [inserted_at: :asc])

      prepare fn query, _context ->
        Ash.Query.before_action(query, &TeacherAssistant.Tenancy.require_tenant/1)
      end
    end

    # Global read (no tenant): a user's schools must be listable before a
    # tenant is chosen.
    read :active_for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id) and active == true)
      prepare build(load: [:workspace], sort: [inserted_at: :asc])
    end

    # Tenant scoping (attribute multitenancy) already restricts this to the
    # given workspace; no `workspace_id` argument is needed any more. See
    # `:active_for_workspace` above for why `Tenancy.require_tenant/1` is needed.
    read :for_workspace_and_user do
      argument :user_id, :uuid, allow_nil?: false
      get? true

      filter expr(user_id == ^arg(:user_id) and active == true)

      prepare fn query, _context ->
        Ash.Query.before_action(query, &TeacherAssistant.Tenancy.require_tenant/1)
      end
    end

    update :deactivate do
      change set_attribute(:active, false)
    end
  end

  policies do
    policy action(:active_for_user) do
      authorize_if expr(user_id == ^actor(:id))
    end

    policy action([:read, :active_for_workspace, :for_workspace_and_user]) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update, :destroy]) do
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

    attribute :roles, {:array, TeacherAssistant.Accounts.SchoolRole},
      allow_nil?: false,
      public?: true

    attribute :status, TeacherAssistant.Accounts.MembershipStatus, allow_nil?: true, public?: true
    attribute :active, :boolean, allow_nil?: false, default: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :user, TeacherAssistant.Accounts.User do
      source_attribute :user_id
      allow_nil? false
      public? true
    end
  end

  aggregates do
    # Count of other active head memberships in the same workspace (self
    # excluded) — backs the "can't remove/deactivate the last head" guard in
    # `TeacherAssistant.Accounts`.
    count :other_active_heads, __MODULE__ do
      filter expr(
               workspace_id == parent(workspace_id) and active == true and :head in roles and
                 id != parent(id)
             )
    end
  end

  identities do
    identity :unique_member, [:workspace_id, :user_id]
  end
end
