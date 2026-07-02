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
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :roles, {:array, TeacherAssistant.Accounts.SchoolRole}, allow_nil?: false, public?: true
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

  identities do
    identity :unique_member, [:workspace_id, :user_id]
  end
end
