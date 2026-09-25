defmodule TeacherAssistant.Academics.LessonPlan do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "lesson_plans"
    repo TeacherAssistant.Repo

    custom_indexes do
      # Composite-FK target: attribute multitenancy prefixes this to
      # (workspace_id, id), the unique key that tenant-matched references need.
      index [:id], unique: true
    end

    references do
      reference :progression_entry,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end
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

    # The (at most one, per `unique_entry`) lesson plan of a progression
    # entry. Mirrors the old `Academics.get_lesson_plan_for_entry/1`.
    read :for_entry do
      argument :progression_entry_id, :uuid, allow_nil?: false
      filter expr(progression_entry_id == ^arg(:progression_entry_id))
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
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

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_entry, [:progression_entry_id]
  end
end
