defmodule TeacherAssistant.Academics.LessonPlan do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "lesson_plans"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :progression_entry_id,
        :lesson_date,
        :duration_minutes,
        :titre,
        :competence_attendue,
        :situation_probleme,
        :objectifs,
        :supports,
        :prerequis
      ],
      update: [
        :lesson_date,
        :duration_minutes,
        :titre,
        :competence_attendue,
        :situation_probleme,
        :objectifs,
        :supports,
        :prerequis
      ]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :lesson_date, :date, allow_nil?: true, public?: true
    attribute :duration_minutes, :integer, default: 55, public?: true
    attribute :titre, :string, allow_nil?: true, public?: true
    attribute :competence_attendue, :string, allow_nil?: true, public?: true
    attribute :situation_probleme, :string, allow_nil?: true, public?: true
    attribute :objectifs, :string, allow_nil?: true, public?: true
    attribute :supports, :string, allow_nil?: true, public?: true
    attribute :prerequis, :string, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :progression_entry, TeacherAssistant.Academics.ProgressionEntry do
      source_attribute :progression_entry_id
      allow_nil? false
      public? true
    end

    has_many :lesson_steps, TeacherAssistant.Academics.LessonStep
  end

  identities do
    identity :unique_entry, [:progression_entry_id]
  end
end
