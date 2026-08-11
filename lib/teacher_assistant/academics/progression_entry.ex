defmodule TeacherAssistant.Academics.ProgressionEntry do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "progression_entries"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :progression_module_id,
        :lesson_title,
        :planned_hours,
        :entry_type,
        :week_no,
        :position,
        :famille_de_situations,
        :categories_action,
        :competence_visee,
        :progression_plan_id,
        :sequence_id
      ],
      update: [
        :progression_module_id,
        :lesson_title,
        :planned_hours,
        :entry_type,
        :week_no,
        :position,
        :famille_de_situations,
        :categories_action,
        :competence_visee,
        :sequence_id
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
    attribute :lesson_title, :string, allow_nil?: false, public?: true
    attribute :planned_hours, :decimal, default: Decimal.new("1"), public?: true

    attribute :entry_type, :atom,
      constraints: [
        one_of: [
          :lesson,
          :integration,
          :evaluation,
          :revision,
          :correction,
          :remediation,
          :holiday
        ]
      ],
      allow_nil?: false,
      default: :lesson,
      public?: true

    attribute :week_no, :integer, allow_nil?: true, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :famille_de_situations, :string, allow_nil?: true, public?: true
    attribute :categories_action, :string, allow_nil?: true, public?: true
    attribute :competence_visee, :string, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :progression_plan, TeacherAssistant.Academics.ProgressionPlan do
      source_attribute :progression_plan_id
      allow_nil? false
      public? true
    end

    belongs_to :sequence, TeacherAssistant.Academics.Sequence do
      source_attribute :sequence_id
      allow_nil? true
      public? true
    end

    belongs_to :progression_module, TeacherAssistant.Academics.ProgressionModule do
      source_attribute :progression_module_id
      allow_nil? false
      public? true
    end
  end
end
