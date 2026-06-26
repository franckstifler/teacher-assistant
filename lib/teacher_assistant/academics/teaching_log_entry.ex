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
      create: [:date, :content_taught, :hours, :status, :homework, :note, :personal_workspace_id, :progression_entry_id],
      update: [:date, :content_taught, :hours, :status, :homework, :note, :progression_entry_id]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :date, :date, allow_nil?: false, public?: true
    attribute :content_taught, :string, allow_nil?: false, public?: true
    attribute :hours, :decimal, default: Decimal.new("1"), public?: true
    attribute :status, :atom, constraints: [one_of: [:done, :partial]], default: :done, allow_nil?: false, public?: true
    attribute :homework, :string, allow_nil?: true, public?: true
    attribute :note, :string, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :personal_workspace, TeacherAssistant.Academics.PersonalWorkspace do
      source_attribute :personal_workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :progression_entry, TeacherAssistant.Academics.ProgressionEntry do
      source_attribute :progression_entry_id
      allow_nil? true
      public? true
    end
  end
end
