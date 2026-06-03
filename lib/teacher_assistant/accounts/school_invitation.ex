defmodule TeacherAssistant.Accounts.SchoolInvitation do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Accounts

  postgres do
    table "school_invitations"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:email, :role, :token, :status, :school_id, :invited_by_user_id]
    end

    update :accept do
      accept [:status, :accepted_by_user_id, :accepted_at]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :email, :ci_string, allow_nil?: false, public?: true

    attribute :role, TeacherAssistant.Accounts.UserRole,
      allow_nil?: false,
      default: :teacher,
      public?: true

    attribute :token, :string, allow_nil?: false, public?: true

    attribute :status, TeacherAssistant.Accounts.InvitationStatus,
      allow_nil?: false,
      default: :pending,
      public?: true

    attribute :accepted_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School, allow_nil?: false
    belongs_to :invited_by_user, TeacherAssistant.Accounts.User, allow_nil?: false
    belongs_to :accepted_by_user, TeacherAssistant.Accounts.User, allow_nil?: true
  end

  identities do
    identity :unique_token, [:token]
  end
end
