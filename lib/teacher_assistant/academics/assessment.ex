defmodule TeacherAssistant.Academics.Assessment do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "assessments"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:label, :weight, :max_score, :given_on, :teaching_context_id, :sequence_id],
      update: [:label, :weight, :max_score, :given_on]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :label, :string, allow_nil?: false, public?: true
    attribute :weight, :decimal, allow_nil?: false, default: Decimal.new(1), public?: true
    attribute :max_score, :decimal, allow_nil?: false, default: Decimal.new(20), public?: true
    attribute :given_on, :date, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? false
      public? true
    end

    belongs_to :sequence, TeacherAssistant.Academics.Sequence do
      source_attribute :sequence_id
      allow_nil? false
      public? true
    end
  end
end
