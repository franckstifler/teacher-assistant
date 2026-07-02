defmodule TeacherAssistant.Academics.Workspace do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspaces"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:name, :kind, :owner_user_id],
      update: [:name]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true

    attribute :kind, TeacherAssistant.Accounts.WorkspaceKind,
      allow_nil?: false,
      default: :personal,
      public?: true

    timestamps()
  end

  relationships do
    belongs_to :owner_user, TeacherAssistant.Accounts.User do
      source_attribute :owner_user_id
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :unique_owner_user, [:owner_user_id]
  end
end
