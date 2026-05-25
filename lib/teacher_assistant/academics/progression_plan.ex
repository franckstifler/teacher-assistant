defmodule TeacherAssistant.Academics.ProgressionPlan do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "progression_plans"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [
      :academic_year_id,
      :classroom_id,
      :level_option_subject_id,
      :teacher_id,
      :weekly_hours,
      :annual_hours,
      :status
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

    attribute :weekly_hours, :decimal, public?: true, allow_nil?: false, default: Decimal.new("0")
    attribute :annual_hours, :decimal, public?: true, allow_nil?: false, default: Decimal.new("0")

    attribute :status, TeacherAssistant.Academics.Enums.ProgressionPlanStatus,
      public?: true,
      allow_nil?: false,
      default: :draft

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear, allow_nil?: false
    belongs_to :classroom, TeacherAssistant.Academics.Classroom, allow_nil?: false

    belongs_to :level_option_subject, TeacherAssistant.Academics.LevelOptionSubject,
      allow_nil?: false

    belongs_to :teacher, TeacherAssistant.Accounts.User, allow_nil?: false
    has_many :entries, TeacherAssistant.Academics.ProgressionEntry
  end

  identities do
    identity :unique_teacher_progression_plan, [
      :school_id,
      :academic_year_id,
      :classroom_id,
      :level_option_subject_id,
      :teacher_id
    ]
  end
end
