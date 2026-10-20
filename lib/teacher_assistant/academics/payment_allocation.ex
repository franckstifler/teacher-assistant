defmodule TeacherAssistant.Academics.PaymentAllocation do
  @moduledoc """
  The share of a payment that went to one fee type (Fees 1), written once when the
  payment is recorded, with the student's frozen paid-to-date and left for that type.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Fees,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "payment_allocations"
    repo TeacherAssistant.Repo

    references do
      reference :payment,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :fee_type,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end

    check_constraints do
      check_constraint :amount, "payment_allocations_amount_positive_check",
        check: "amount > 0",
        message: "must be positive"
    end
  end

  actions do
    defaults [:read, create: [:payment_id, :fee_type_id, :amount, :paid_to_date, :left_after]]
  end

  policies do
    policy action_type(:read) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :fees}
      authorize_if expr(payment.enrollment.class_group.form_master_user_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if {Checks.SchoolRole, any_of: :fees}
    end
  end

  validations do
    validate {TeacherAssistant.Academics.YearOpen, path: [:payment]}, on: [:create]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :amount, :integer, allow_nil?: false, public?: true
    attribute :paid_to_date, :integer, allow_nil?: false, public?: true
    attribute :left_after, :integer, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :payment, TeacherAssistant.Academics.Payment do
      source_attribute :payment_id
      allow_nil? false
      public? true
    end

    belongs_to :fee_type, TeacherAssistant.Academics.FeeType do
      source_attribute :fee_type_id
      allow_nil? false
      public? true
    end
  end
end
