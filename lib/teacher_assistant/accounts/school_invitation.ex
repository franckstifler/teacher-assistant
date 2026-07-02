defmodule TeacherAssistant.Accounts.SchoolInvitation do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "school_invitations"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:workspace_id, :email, :roles, :invited_by_user_id, :status, :token, :expires_at],
      update: [:status]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
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
    identity :unique_token, [:token]
  end
end
