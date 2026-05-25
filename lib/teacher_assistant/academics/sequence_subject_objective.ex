defmodule TeacherAssistant.Academics.SequenceSubjectObjective do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource]

  postgres do
    table "sequences_subjects_objectives"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [:objective, :sequence_id, :level_option_subject_id]
    defaults [:read, :destroy]

    create :create do
      primary? true
    end

    update :update do
      primary? true
      require_atomic? false
    end
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :objective, :string, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :sequence, TeacherAssistant.Academics.Sequence, allow_nil?: false

    belongs_to :level_option_subject, TeacherAssistant.Academics.LevelOptionSubject,
      allow_nil?: false
  end

  identities do
    identity :unique_sequence_subject, [:school_id, :sequence_id, :level_option_subject_id]
  end
end
