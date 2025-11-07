defmodule TeacherAssistant.Academics.Classroom do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource]

  postgres do
    table "classrooms"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear, allow_nil?: false
    belongs_to :level_option, TeacherAssistant.Academics.LevelOption, allow_nil?: false
  end

  identities do
    identity :name, [:academic_year_id, :level_option_id]
  end
end
