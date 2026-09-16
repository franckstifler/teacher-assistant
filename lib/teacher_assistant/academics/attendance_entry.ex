defmodule TeacherAssistant.Academics.AttendanceEntry do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "attendance_entries"
    repo TeacherAssistant.Repo

    references do
      reference :enrollment, on_delete: :delete
      reference :period, on_delete: :delete
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :date,
        :status,
        :justified,
        :justification_note,
        :recorded_by_user_id,
        :workspace_id,
        :enrollment_id,
        :period_id,
        :teaching_context_id
      ],
      update: [
        :date,
        :status,
        :justified,
        :justification_note,
        :recorded_by_user_id
      ]
    ]

    create :record do
      accept [
        :status,
        :justified,
        :justification_note,
        :teaching_context_id,
        :recorded_by_user_id,
        :workspace_id,
        :enrollment_id,
        :date,
        :period_id
      ]

      upsert? true
      upsert_identity :unique_mark
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :date, :date, allow_nil?: false, public?: true

    attribute :status, TeacherAssistant.Academics.AttendanceStatus,
      allow_nil?: false,
      public?: true

    attribute :justified, :boolean, allow_nil?: false, default: false, public?: true
    attribute :justification_note, :string, allow_nil?: true, public?: true
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

    belongs_to :period, TeacherAssistant.Academics.Period do
      source_attribute :period_id
      allow_nil? false
      public? true
    end

    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :unique_mark, [:enrollment_id, :date, :period_id]
  end
end
