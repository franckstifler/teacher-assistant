defmodule TeacherAssistant.Academics.LessonStep do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "lesson_steps"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :lesson_plan_id,
        :position,
        :etape,
        :duration_minutes,
        :contenus,
        :supports,
        :activites
      ],
      update: [:position, :etape, :duration_minutes, :contenus, :supports, :activites]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :etape, :string, allow_nil?: true, public?: true
    attribute :duration_minutes, :integer, allow_nil?: true, public?: true
    attribute :contenus, :string, allow_nil?: true, public?: true
    attribute :supports, :string, allow_nil?: true, public?: true
    attribute :activites, :string, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :lesson_plan, TeacherAssistant.Academics.LessonPlan do
      source_attribute :lesson_plan_id
      allow_nil? false
      public? true
    end
  end
end
