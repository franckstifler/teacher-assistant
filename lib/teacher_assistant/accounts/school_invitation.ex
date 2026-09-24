defmodule TeacherAssistant.Accounts.SchoolInvitation do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

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
      prepare build(load: [:workspace])
    end

    # Tenant scoping (attribute multitenancy) already restricts this to the
    # given workspace; no `workspace_id` argument is needed any more.
    read :pending_for_workspace do
      filter expr(status == :pending)
      prepare build(sort: [inserted_at: :asc])
    end

    update :revoke do
      change set_attribute(:status, :revoked)
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
end
