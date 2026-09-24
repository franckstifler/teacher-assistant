defmodule TeacherAssistant.Accounts.SchoolMembership do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

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
    # The resource stays `global? true` (`:active_for_user` and `:by_token`
    # on `SchoolInvitation` need that), which means Ash's own per-action
    # `multitenancy :enforce` (declared below for documentation) does not by
    # itself make a missing tenant an error here — a `global? true` resource
    # is allowed to run any of its actions without one. Without a tenant this
    # filter would otherwise run unscoped across every workspace (a silent
    # global read), so `require_tenant/1` raises `Ash.Error.Invalid` first —
    # registered via `Ash.Query.before_action/2` (not run inline in
    # `prepare`) because callers set the tenant with a separate
    # `Ash.Query.set_tenant/2` call *after* `for_read/3` returns; a plain
    # `prepare` runs during `for_read/3` itself, before that later call, so
    # it would always see `query.tenant == nil` and reject every call.
    read :active_for_workspace do
      multitenancy :enforce
      filter expr(active == true)
      prepare build(load: [:user], sort: [inserted_at: :asc])
      prepare fn query, _context -> Ash.Query.before_action(query, &require_tenant/1) end
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
    # `:active_for_workspace` above for why `require_tenant/1` is needed
    # despite `multitenancy :enforce`.
    read :for_workspace_and_user do
      multitenancy :enforce
      argument :user_id, :uuid, allow_nil?: false
      get? true

      filter expr(user_id == ^arg(:user_id) and active == true)
      prepare fn query, _context -> Ash.Query.before_action(query, &require_tenant/1) end
    end

    update :deactivate do
      change set_attribute(:active, false)
    end
  end

  policies do
    policy always() do
      authorize_if always()
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

  # This resource is `global? true` (see the `multitenancy` block above), so
  # Ash lets any of its actions run without a tenant. A tenant-scoped read
  # (`:active_for_workspace`, `:for_workspace_and_user`) must not silently
  # fall back to an unscoped, cross-workspace read when the caller forgets to
  # set one — so this `prepare` raises explicitly instead.
  defp require_tenant(query) do
    if query.tenant do
      query
    else
      Ash.Query.add_error(
        query,
        Ash.Error.Invalid.TenantRequired.exception(resource: query.resource)
      )
    end
  end
end
