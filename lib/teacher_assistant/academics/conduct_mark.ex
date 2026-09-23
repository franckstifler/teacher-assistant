defmodule TeacherAssistant.Academics.ConductMark do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Discipline,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "conduct_marks"
    repo TeacherAssistant.Repo

    references do
      reference :enrollment, on_delete: :delete, index?: true
      reference :sequence, on_delete: :delete, index?: true
      reference :workspace, on_delete: :delete, index?: true
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

    read :for_enrollment_sequence do
      argument :enrollment_id, :uuid, allow_nil?: false
      argument :sequence_id, :uuid, allow_nil?: false

      filter expr(enrollment_id == ^arg(:enrollment_id) and sequence_id == ^arg(:sequence_id))
    end

    read :for_enrollment_sequences do
      argument :enrollment_id, :uuid, allow_nil?: false
      argument :sequence_ids, {:array, :uuid}, allow_nil?: false

      filter expr(enrollment_id == ^arg(:enrollment_id) and sequence_id in ^arg(:sequence_ids))
    end

    read :for_enrollments_sequences do
      argument :enrollment_ids, {:array, :uuid}, allow_nil?: false
      argument :sequence_ids, {:array, :uuid}, allow_nil?: false

      filter expr(enrollment_id in ^arg(:enrollment_ids) and sequence_id in ^arg(:sequence_ids))
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

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_conduct_mark, [:enrollment_id, :sequence_id]
  end
end
