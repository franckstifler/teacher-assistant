defmodule TeacherAssistant.Academics.LessonPlanEntry do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "lesson_plan_entries"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:title, :planned_on, :planned_hours, :objectives, :personal_classroom_id],
      update: [:title, :planned_on, :planned_hours, :objectives]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :planned_on, :date, allow_nil?: false, public?: true

    attribute :planned_hours, :decimal,
      allow_nil?: false,
      default: Decimal.new("1.0"),
      public?: true

    attribute :objectives, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :personal_classroom, TeacherAssistant.Academics.PersonalClassroom do
      allow_nil? false
      public? true
    end

    has_many :teaching_logs, TeacherAssistant.Academics.TeachingLogEntry
  end
end
