defmodule TeacherAssistant.Academics.Subject do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource]

  postgres do
    table "subjects"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [:name, :description, :default_coefficient]
    defaults [:create, :update, :read, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :description, :string, public?: true
    attribute :default_coefficient, :integer, public?: true, default: 1, constraints: [min: 1]

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
  end

  identities do
    identity :unique_name, [:school_id, :name]
  end
end
