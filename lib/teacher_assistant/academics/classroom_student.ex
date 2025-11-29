defmodule TeacherAssistant.Academics.ClassroomStudent do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource]

  postgres do
    table "classrooms_students"
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
    belongs_to :classroom, TeacherAssistant.Academics.Classroom, allow_nil?: false, public?: true
    belongs_to :student, TeacherAssistant.Academics.Student, allow_nil?: false, public?: true
  end

  identities do
    identity :classroom_student, [:classroom_id, :student_id]
  end
end
