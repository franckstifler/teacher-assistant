defmodule TeacherAssistant.Academics.Option do
  use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: TeacherAssistant.Academics

  postgres do
    repo Ap.Repo
    table "options"
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

    attribute :description, :string, public?: true
    attribute :name, :string, public?: true, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
  end

  identities do
    identity :name, [:name]
  end
end
