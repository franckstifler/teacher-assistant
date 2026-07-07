defmodule TeacherAssistant.Academics.TimetableSlot do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "timetable_slots"
    repo TeacherAssistant.Repo

    references do
      reference :class_group, on_delete: :delete
      reference :teaching_context, on_delete: :delete
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:class_group_id, :teaching_context_id, :period_id, :day, :workspace_id],
      update: [:class_group_id, :teaching_context_id, :period_id, :day, :workspace_id]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :day, TeacherAssistant.Academics.DayOfWeek,
      allow_nil?: false,
      public?: true

    attribute :workspace_id, :uuid, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end

    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? false
      public? true
    end

    belongs_to :period, TeacherAssistant.Academics.Period do
      source_attribute :period_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_cell, [:class_group_id, :day, :period_id]
  end
end
