defmodule TeacherAssistant.Accounts.UserSchool do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Accounts

  postgres do
    table "users_schools"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:user_id, :role]
    end

    update :update do
      primary? true
      accept [:role]
    end
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :role, TeacherAssistant.Accounts.UserRole,
      public?: true,
      allow_nil?: false,
      default: :teacher

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School, allow_nil?: false
    belongs_to :user, TeacherAssistant.Accounts.User, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_user_school, [:school_id, :user_id]
  end
end
