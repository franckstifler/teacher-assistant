defmodule TeacherAssistant.Academics.Mark do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource]

  postgres do
    table "marks"
    repo TeacherAssistant.Repo
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  actions do
    default_accept [:score, :comment, :student_id, :classroom_id, :sequence_id, :level_option_subject_id]
    defaults [:read, :destroy]

    create :create do
      primary? true
    end

    update :update do
      primary? true
      require_atomic? false
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :score, :decimal, allow_nil?: false, public?: true
    attribute :comment, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :student, TeacherAssistant.Academics.Student, allow_nil?: false
    belongs_to :classroom, TeacherAssistant.Academics.Classroom, allow_nil?: false
    belongs_to :sequence, TeacherAssistant.Academics.Sequence, allow_nil?: false
    belongs_to :level_option_subject, TeacherAssistant.Academics.LevelOptionSubject, allow_nil?: false
  end

  identities do
    identity :unique_mark,
      [:school_id, :student_id, :level_option_subject_id, :sequence_id]
  end
end
