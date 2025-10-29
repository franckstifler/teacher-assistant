defmodule TeacherAssistant.Academics.Level do
  use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: TeacherAssistant.Academics

  postgres do
    repo TeacherAssistant.Repo
    table "levels"
  end

  actions do
    default_accept [:name, :description]
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

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
  end

  identities do
    identity :unique_name, [:name]
  end
end
