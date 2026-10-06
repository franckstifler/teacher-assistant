defmodule TeacherAssistant.Academics.EntryReminder do
  @moduledoc """
  Spec KLM8 (N06): a « Relancer » sent to a course's teacher for one séquence. At most
  one per course, séquence and school day (`sent_on`, the school-local date).
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks
  alias TeacherAssistant.Academics.Reference

  postgres do
    table "entry_reminders"
    repo TeacherAssistant.Repo

    references do
      reference :teaching_context,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :sequence,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :sent_by, on_delete: :nilify
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:teaching_context_id, :sequence_id]
      change set_attribute(:sent_by_user_id, actor(:id))
      change set_attribute(:sent_on, &Reference.today/0)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end

    policy action(:create) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :sent_on, :date, allow_nil?: false, public?: true
    create_timestamp :inserted_at
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

    belongs_to :sent_by, TeacherAssistant.Accounts.User do
      source_attribute :sent_by_user_id
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    # Course ids are unique across schools, so the school need not be part of the key.
    identity :once_a_day, [:teaching_context_id, :sequence_id, :sent_on], all_tenants?: true
  end
end
