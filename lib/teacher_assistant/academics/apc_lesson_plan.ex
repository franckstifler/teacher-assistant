defmodule TeacherAssistant.Academics.ApcLessonPlan do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource]

  postgres do
    table "apc_lesson_plans"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [
      :progression_entry_id,
      :competence,
      :prerequisites,
      :situation_problem,
      :learning_activities,
      :resources,
      :evaluation,
      :remediation,
      :duration_minutes
    ]

    defaults [:create, :read, :update, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :competence, :string, public?: true, allow_nil?: false
    attribute :prerequisites, :string, public?: true
    attribute :situation_problem, :string, public?: true
    attribute :learning_activities, :string, public?: true
    attribute :resources, :string, public?: true
    attribute :evaluation, :string, public?: true
    attribute :remediation, :string, public?: true
    attribute :duration_minutes, :integer, public?: true, constraints: [min: 1]

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :progression_entry, TeacherAssistant.Academics.ProgressionEntry, allow_nil?: false
  end
end
