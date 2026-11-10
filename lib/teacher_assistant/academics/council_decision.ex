defmodule TeacherAssistant.Academics.CouncilDecision do
  @moduledoc """
  The class council's decision for one student (spec I3): a distinction choice (nil keeps
  the I1 proposal), an optional conduct warning and a free-text appreciation. One row per
  council and student, recorded by upsert.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "council_decisions"
    repo TeacherAssistant.Repo

    references do
      reference :class_council,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :student,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [
        :class_council_id,
        :student_id,
        :distinction_choice,
        :conduct_warning,
        :appreciation,
        :passage_decision
      ]

      upsert? true
      upsert_identity :one_per_student

      upsert_fields [
        :distinction_choice,
        :conduct_warning,
        :appreciation,
        :passage_decision,
        :updated_at
      ]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action(:record) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  changes do
    change {TeacherAssistant.Academics.YearOpen, path: [:class_council]},
      on: [:create, :update, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :distinction_choice, TeacherAssistant.Academics.CouncilDistinctionChoice,
      public?: true

    attribute :conduct_warning, TeacherAssistant.Academics.ConductWarning, public?: true
    attribute :appreciation, :string, public?: true, constraints: [max_length: 300]

    # Annual council only (spec I4); nil keeps the proposal.
    attribute :passage_decision, TeacherAssistant.Academics.PassageDecision, public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :class_council, TeacherAssistant.Academics.ClassCouncil do
      source_attribute :class_council_id
      allow_nil? false
      public? true
    end

    belongs_to :student, TeacherAssistant.Academics.Student do
      source_attribute :student_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_per_student, [:class_council_id, :student_id]
  end
end
