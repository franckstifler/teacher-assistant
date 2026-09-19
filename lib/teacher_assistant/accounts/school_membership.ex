defmodule TeacherAssistant.Accounts.SchoolMembership do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "school_memberships"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:workspace_id, :user_id, :roles, :status, :active],
      update: [:roles, :status, :active]
    ]

    read :active_for_workspace do
      argument :workspace_id, :uuid, allow_nil?: false
      filter expr(workspace_id == ^arg(:workspace_id) and active == true)
      prepare build(load: [:user], sort: [inserted_at: :asc])
    end

    read :active_for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id) and active == true)
      prepare build(load: [:workspace])
    end

    read :for_workspace_and_user do
      argument :workspace_id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false
      get? true

      filter expr(
               workspace_id == ^arg(:workspace_id) and user_id == ^arg(:user_id) and
                 active == true
             )
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
