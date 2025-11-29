defmodule TeacherAssistant.Academics.Student do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource]

  postgres do
    table "students"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [:first_name, :last_name, :matricule, :place_of_birth, :date_of_birth, :gender]
    defaults [:create, :update, :read, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :first_name, :ci_string, public?: true, allow_nil?: false
    attribute :last_name, :ci_string, public?: true, allow_nil?: false
    attribute :matricule, :string, public?: true
    attribute :place_of_birth, :string, public?: true
    attribute :date_of_birth, :date, public?: true

    attribute :gender, TeacherAssistant.Academics.Enums.Gender,
      public?: true,
      allow_nil?: false,
      default: :male

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
  end

  identities do
    identity :unique_name_and_date_of_birth, [:first_name, :last_name, :date_of_birth]
  end
end
