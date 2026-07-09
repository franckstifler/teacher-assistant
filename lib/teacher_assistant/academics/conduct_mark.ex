defmodule TeacherAssistant.Academics.ConductMark do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "conduct_marks"
    repo TeacherAssistant.Repo

    references do
      reference :enrollment, on_delete: :delete
      reference :sequence, on_delete: :delete
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:value, :recorded_by_user_id, :workspace_id, :enrollment_id, :sequence_id],
      update: [:value, :recorded_by_user_id]
    ]

    create :set do
      accept [:value, :recorded_by_user_id, :workspace_id, :enrollment_id, :sequence_id]

      upsert? true
      upsert_identity :unique_conduct_mark
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :value, :decimal, allow_nil?: false, public?: true
    attribute :recorded_by_user_id, :uuid, allow_nil?: true, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :enrollment, TeacherAssistant.Academics.Enrollment do
      source_attribute :enrollment_id
      allow_nil? false
      public? true
    end

    belongs_to :sequence, TeacherAssistant.Academics.Sequence do
      source_attribute :sequence_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_conduct_mark, [:enrollment_id, :sequence_id]
  end
end
