defmodule TeacherAssistant.Academics.Payment do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Fees,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "payments"
    repo TeacherAssistant.Repo

    custom_indexes do
      # FK-leading index for delete-time FK checks — the tenancy migration
      # replaced this with `(workspace_id, enrollment_id)`. `all_tenants?:
      # true` keeps this plain (no automatic `workspace_id` prefix).
      index [:enrollment_id], all_tenants?: true

      # Composite-FK target for allocations: attribute multitenancy prefixes this to (workspace_id, id).
      index [:id], unique: true
    end

    references do
      # Fees 1: a receipt outlives everything — an enrollment with payments cannot be deleted.
      reference :enrollment,
        on_delete: :restrict,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :academic_year,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end

    check_constraints do
      check_constraint :amount, "payments_amount_positive_check",
        check: "amount > 0",
        message: "must be positive"
    end
  end

  actions do
    # Fees 1: a payment is its receipt — created once, never updated or deleted; a mistake
    # is cancelled (with a reason) and recorded again.
    defaults [
      :read,
      create: [
        :amount,
        :paid_on,
        :method,
        :reference,
        :note,
        :enrollment_id,
        :academic_year_id
        # seq, number, paid_to_date, left_after, recorded_by_user_id, student_name and
        # class_label are set by `Fees.record_payment/3` under its numbering lock.
      ]
    ]

    update :cancel do
      require_atomic? false
      accept []

      argument :reason, :string,
        allow_nil?: false,
        constraints: [trim?: true, allow_empty?: false]

      validate attribute_equals(:status, :valid), message: "receipt already cancelled"

      change set_attribute(:status, :cancelled)
      change set_attribute(:cancel_reason, arg(:reason))
      change set_attribute(:cancelled_at, &DateTime.utc_now/0)

      change fn changeset, context ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :cancelled_by_user_id,
          context.actor && context.actor.id
        )
      end
    end

    read :for_enrollment do
      argument :enrollment_id, :uuid, allow_nil?: false
      filter expr(enrollment_id == ^arg(:enrollment_id))
      prepare build(sort: [seq: :desc], load: [allocations: :fee_type])
    end

    read :for_enrollment_ids do
      argument :enrollment_ids, {:array, :uuid}, allow_nil?: false
      filter expr(enrollment_id in ^arg(:enrollment_ids))
    end
  end

  policies do
    policy action_type(:read) do
      # Row rules name a user, not a membership: require an active one.
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :fees}
      authorize_if expr(enrollment.class_group.form_master_user_id == ^actor(:id))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :fees}
    end
  end

  changes do
    change {TeacherAssistant.Academics.YearOpen, path: []}, on: [:create, :update]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :amount, :integer, allow_nil?: false, public?: true
    attribute :paid_on, :date, allow_nil?: false, public?: true

    attribute :method, TeacherAssistant.Academics.PaymentMethod,
      allow_nil?: false,
      public?: true

    attribute :reference, :string, allow_nil?: true, public?: true
    attribute :note, :string, allow_nil?: true, public?: true
    attribute :recorded_by_user_id, :uuid, allow_nil?: true, public?: true

    # Fees 1: the receipt number (`R2026-000123`) from `seq`, per school and year.
    attribute :seq, :integer, allow_nil?: false, public?: true
    attribute :number, :string, allow_nil?: false, public?: true

    attribute :status, TeacherAssistant.Academics.PaymentStatus,
      allow_nil?: false,
      default: :valid,
      public?: true

    # Frozen when the receipt is issued: the student's total paid this year and the
    # balance left, counting this payment.
    attribute :paid_to_date, :integer, allow_nil?: false, public?: true
    attribute :left_after, :integer, allow_nil?: false, public?: true
    # …and who it was for, as printed (a later transfer or rename does not change the receipt).
    attribute :student_name, :string, allow_nil?: false, public?: true
    attribute :class_label, :string, allow_nil?: false, public?: true

    attribute :cancelled_at, :utc_datetime_usec, allow_nil?: true, public?: true
    attribute :cancelled_by_user_id, :uuid, allow_nil?: true, public?: true
    attribute :cancel_reason, :string, allow_nil?: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :enrollment, TeacherAssistant.Academics.Enrollment do
      source_attribute :enrollment_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    has_many :allocations, TeacherAssistant.Academics.PaymentAllocation
  end

  identities do
    identity :unique_receipt, [:academic_year_id, :seq]
  end
end
