defmodule TeacherAssistant.Academics.TeachingLogEntry do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "teaching_log_entries"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:taught_on, :taught_hours, :notes, :lesson_plan_entry_id],
      update: [:taught_on, :taught_hours, :notes]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :taught_on, :date, allow_nil?: false, public?: true

    attribute :taught_hours, :decimal,
      allow_nil?: false,
      default: Decimal.new("1.0"),
      public?: true

    attribute :notes, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :lesson_plan_entry, TeacherAssistant.Academics.LessonPlanEntry do
      allow_nil? false
      public? true
    end
  end
end
