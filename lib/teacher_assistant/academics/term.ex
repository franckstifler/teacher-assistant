defmodule TeacherAssistant.Academics.Term do
  use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: TeacherAssistant.Academics

  postgres do
    repo TeacherAssistant.Repo
    table "terms"
  end

  actions do
    default_accept [:name, :start_date, :end_date]
    defaults [:create, :update, :read, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :start_date, :date, public?: true
    attribute :end_date, :date, public?: true
    attribute :position, :integer

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssitant.Academics.School
    belongs_to :academic_year, TeacherAssitant.Academics.AcademicYear, allow_nil?: false
  end

  identities do
    identity :name, [:name]
  end
end
