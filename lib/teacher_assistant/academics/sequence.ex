defmodule TeacherAssistant.Academics.Sequence do
  use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: TeacherAssistant.Academics

  postgres do
    repo TeacherAssistant.Repo
    table "sequences"
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
    uuid_primary_key :id
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :start_date, :date, public?: true
    attribute :end_date, :date, public?: true

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssitant.Academics.School
    belongs_to :term, TeacherAssistant.Academics.Term, allow_nil?: false
  end
end
