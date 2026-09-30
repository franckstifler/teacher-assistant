defmodule TeacherAssistant.Academics.MarkEvent do
  @moduledoc """
  The marks journal (spec D3a): one append-only row per mark change or correction step,
  written in the same transaction as the change. Values are snapshots (`nil` status =
  blank, "not entered"). The rows outlive the marks, assessments and students they
  describe, so `assessment_id`/`student_id` carry no foreign key.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "mark_events"
    repo TeacherAssistant.Repo

    references do
      reference :assessment, ignore?: true
      reference :student, ignore?: true
      reference :actor, on_delete: :nilify
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :action,
        :actor_user_id,
        :assessment_id,
        :student_id,
        :before_status,
        :before_score,
        :after_status,
        :after_score,
        :batch_id,
        :mark_correction_id
      ]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end

    # Rows are written only by the mark and correction changes, which bypass this
    # (`authorize?: false`): nobody records, edits or deletes journal rows through an
    # action.
    policy action(:record) do
      forbid_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :action, TeacherAssistant.Academics.MarkEventAction,
      allow_nil?: false,
      public?: true

    # nil = the system.
    attribute :actor_user_id, :uuid, public?: true
    attribute :before_status, TeacherAssistant.Academics.MarkStatus, public?: true
    attribute :before_score, :decimal, public?: true
    attribute :after_status, TeacherAssistant.Academics.MarkStatus, public?: true
    attribute :after_score, :decimal, public?: true
    # Shared by the rows of one save.
    attribute :batch_id, :uuid, public?: true
    attribute :mark_correction_id, :uuid, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :assessment, TeacherAssistant.Academics.Assessment do
      source_attribute :assessment_id
      allow_nil? false
      public? true
    end

    belongs_to :student, TeacherAssistant.Academics.Student do
      source_attribute :student_id
      allow_nil? false
      public? true
    end

    belongs_to :actor, TeacherAssistant.Accounts.User do
      source_attribute :actor_user_id
      define_attribute? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end
end
