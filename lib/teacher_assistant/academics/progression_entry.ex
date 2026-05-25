defmodule TeacherAssistant.Academics.ProgressionEntry do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "progression_entries"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [
      :progression_plan_id,
      :term_id,
      :sequence_id,
      :week_number,
      :start_date,
      :end_date,
      :title,
      :planned_content,
      :planned_hours,
      :entry_type
    ]

    defaults [:create, :read, :update, :destroy]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action_type([:create, :update]) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :teacher)
      authorize_if actor_attribute_equals(:role, :principal_teacher)
      authorize_if actor_attribute_equals(:role, :vice_principal)
    end

    policy action_type(:destroy) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :principal)
      authorize_if actor_attribute_equals(:role, :vice_principal)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :week_number, :integer, public?: true, constraints: [min: 1]
    attribute :start_date, :date, public?: true
    attribute :end_date, :date, public?: true
    attribute :title, :string, public?: true, allow_nil?: false
    attribute :planned_content, :string, public?: true

    attribute :planned_hours, :decimal,
      public?: true,
      allow_nil?: false,
      default: Decimal.new("0")

    attribute :entry_type, TeacherAssistant.Academics.Enums.ProgressionEntryType,
      public?: true,
      allow_nil?: false,
      default: :lesson

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :progression_plan, TeacherAssistant.Academics.ProgressionPlan, allow_nil?: false
    belongs_to :term, TeacherAssistant.Academics.Term
    belongs_to :sequence, TeacherAssistant.Academics.Sequence
    has_many :teaching_logs, TeacherAssistant.Academics.TeachingLog
    has_many :apc_lesson_plans, TeacherAssistant.Academics.ApcLessonPlan
  end
end
