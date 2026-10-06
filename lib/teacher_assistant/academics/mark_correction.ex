defmodule TeacherAssistant.Academics.MarkCorrection do
  @moduledoc """
  A request to change a locked mark (spec D3c): the course's teacher asks, an admin
  (Censeur/Proviseur) approves or refuses. Approval is the only way a locked mark
  changes. The mark's value at request time is kept: if it has changed since, the
  request is stale and cannot be approved.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks
  alias TeacherAssistant.Academics.MarkCorrection.{Decide, Request}

  postgres do
    table "mark_corrections"
    repo TeacherAssistant.Repo

    identity_wheres_to_sql one_pending_per_mark: "status = 'pending'"

    references do
      reference :assessment,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :student,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :requester, on_delete: :nilify
      reference :decider, on_delete: :nilify
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    create :request do
      validate {TeacherAssistant.Academics.YearOpen, path: [:assessment, :sequence, :term]}
      accept [:assessment_id, :student_id, :requested_status, :requested_score, :motive]
      change set_attribute(:requester_user_id, actor(:id))
      change set_attribute(:status, :pending)
      change Request
    end

    update :approve do
      validate {TeacherAssistant.Academics.YearOpen, path: [:assessment, :sequence, :term]}
      require_atomic? false
      change {Decide, decision: :approved}
    end

    update :refuse do
      validate {TeacherAssistant.Academics.YearOpen, path: [:assessment, :sequence, :term]}
      require_atomic? false
      change {Decide, decision: :refused}
    end

    update :mark_seen do
      change set_attribute(:seen_at, expr(now()))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if expr(requester_user_id == ^actor(:id))
    end

    policy action(:request) do
      # Row rules name a user, not a membership: require an active one.
      forbid_unless {Checks.SchoolRole, any_of: :member}
      forbid_unless Checks.SchoolVerified
      authorize_if expr(assessment.teaching_context.teacher_user_id == ^actor(:id))
    end

    policy action([:approve, :refuse]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end

    policy action(:mark_seen) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if expr(requester_user_id == ^actor(:id))
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    # nil = blank ("not entered").
    attribute :requested_status, TeacherAssistant.Academics.MarkStatus, public?: true
    attribute :requested_score, :decimal, public?: true
    attribute :current_status, TeacherAssistant.Academics.MarkStatus, public?: true
    attribute :current_score, :decimal, public?: true

    attribute :motive, TeacherAssistant.Academics.MarkCorrectionMotive,
      allow_nil?: false,
      public?: true

    attribute :status, TeacherAssistant.Academics.MarkCorrectionStatus,
      allow_nil?: false,
      default: :pending,
      public?: true

    attribute :decided_at, :utc_datetime_usec, public?: true
    # When the requester last saw the decision (menu badge).
    attribute :seen_at, :utc_datetime_usec, public?: true

    timestamps()
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

    belongs_to :requester, TeacherAssistant.Accounts.User do
      source_attribute :requester_user_id
      public? true
    end

    belongs_to :decider, TeacherAssistant.Accounts.User do
      source_attribute :decider_user_id
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_pending_per_mark, [:assessment_id, :student_id], where: expr(status == :pending)
  end
end
