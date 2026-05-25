defmodule TeacherAssistant.Academics.Mark do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource]

  postgres do
    table "marks"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [
      :score,
      :comment,
      :student_id,
      :classroom_id,
      :sequence_id,
      :level_option_subject_id
    ]

    defaults [:read, :destroy]

    create :create do
      primary? true
      upsert? true
      upsert_identity :unique_mark
    end

    read :by_sequence_and_classroom do
      argument :sequence_id, :uuid_v7, allow_nil?: false
      argument :classroom_id, :uuid_v7, allow_nil?: false
      argument :level_option_subject_id, :uuid_v7

      filter expr(
               sequence_id == ^arg(:sequence_id) and
                 classroom_id == ^arg(:classroom_id) and
                 (is_nil(^arg(:level_option_subject_id)) or
                    level_option_subject_id == ^arg(:level_option_subject_id))
             )
    end
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :score, :decimal,
      public?: true,
      allow_nil?: false,
      constraints: [
        min: Decimal.new("0"),
        max: Decimal.new("20")
      ]

    attribute :comment, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :student, TeacherAssistant.Academics.Student, allow_nil?: false, public?: true
    belongs_to :classroom, TeacherAssistant.Academics.Classroom, allow_nil?: false, public?: true
    belongs_to :sequence, TeacherAssistant.Academics.Sequence, allow_nil?: false, public?: true

    belongs_to :level_option_subject, TeacherAssistant.Academics.LevelOptionSubject,
      allow_nil?: false,
      public?: true
  end

  calculations do
    calculate :subject_name, :string, expr(level_option_subject.subject.name)
    calculate :student_name, :string, expr(student.full_name)
  end

  identities do
    identity :unique_mark, [:school_id, :student_id, :level_option_subject_id, :sequence_id]
  end
end
