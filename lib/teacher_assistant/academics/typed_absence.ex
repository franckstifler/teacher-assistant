defmodule TeacherAssistant.Academics.TypedAbsence do
  @moduledoc """
  Spec 2026-10-30 §2: a student's unjustified absence hours typed by hand for a séquence
  or a trimester (exactly one of the two), counted from the paper roll calls. Read on the
  bulletin path instead of the roll call when the class's source is typed.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Attendance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "typed_absences"
    repo TeacherAssistant.Repo

    # A8: the register and the bulletin read a séquence's or a trimester's figures
    # (attribute multitenancy prefixes workspace_id).
    custom_indexes do
      index [:sequence_id]
      index [:term_id]
    end

    references do
      reference :enrollment,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      # Nullable: `:simple` so a null séquence (or trimester) skips the composite check.
      reference :sequence,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :simple

      reference :term,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :simple

      reference :workspace, on_delete: :delete, index?: true
    end

    check_constraints do
      check_constraint :hours, "typed_absences_hours_check",
        check: "hours >= 0",
        message: "must be greater than or equal to 0"

      check_constraint :sequence_id, "typed_absences_one_period_check",
        check: "(sequence_id IS NULL) <> (term_id IS NULL)",
        message: "a séquence or a trimester, not both"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :set_for_sequence do
      accept [:enrollment_id, :sequence_id, :hours]
      change set_attribute(:recorded_by_user_id, actor(:id))
      upsert? true
      upsert_identity :unique_per_sequence
      upsert_fields [:hours, :recorded_by_user_id, :operator_user_id, :updated_at]
    end

    create :set_for_term do
      accept [:enrollment_id, :term_id, :hours]
      change set_attribute(:recorded_by_user_id, actor(:id))
      upsert? true
      upsert_identity :unique_per_term
      upsert_fields [:hours, :recorded_by_user_id, :operator_user_id, :updated_at]
    end

    read :for_enrollments do
      argument :enrollment_ids, {:array, :uuid}, allow_nil?: false
      filter expr(enrollment_id in ^arg(:enrollment_ids))
    end
  end

  policies do
    policy always() do
      # Row rules name a user, not a membership: require an active one.
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
      authorize_if expr(enrollment.class_group.form_master_user_id == ^actor(:id))
    end
  end

  changes do
    change {TeacherAssistant.Academics.YearOpen, path: [:enrollment]},
      on: [:create, :destroy]

    # Audit follow-ups A6: the operator acting as the member, nil otherwise.
    change {TeacherAssistant.Academics.StampOperator, attribute: :operator_user_id}, on: [:create]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :hours, :decimal, allow_nil?: false, public?: true
    attribute :recorded_by_user_id, :uuid, allow_nil?: true, public?: true
    attribute :operator_user_id, :uuid, allow_nil?: true, public?: true

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
      allow_nil? true
      public? true
    end

    belongs_to :term, TeacherAssistant.Academics.Term do
      source_attribute :term_id
      allow_nil? true
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_per_sequence, [:enrollment_id, :sequence_id]
    identity :unique_per_term, [:enrollment_id, :term_id]
  end
end
