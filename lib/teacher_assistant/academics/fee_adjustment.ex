defmodule TeacherAssistant.Academics.FeeAdjustment do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Fees,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "fee_adjustments"
    repo TeacherAssistant.Repo

    references do
      reference :enrollment,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end

    check_constraints do
      check_constraint :amount, "fee_adjustments_amount_non_zero_check",
        check: "amount <> 0",
        message: "must not be zero"
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:amount, :reason, :recorded_by_user_id, :enrollment_id],
      update: [:amount, :reason, :recorded_by_user_id]
    ]

    create :set do
      accept [:amount, :reason, :recorded_by_user_id, :enrollment_id]

      upsert? true
      upsert_identity :unique_adjustment
    end

    read :for_enrollment do
      argument :enrollment_id, :uuid, allow_nil?: false

      filter expr(enrollment_id == ^arg(:enrollment_id))
    end

    read :for_enrollment_ids do
      argument :enrollment_ids, {:array, :uuid}, allow_nil?: false

      filter expr(enrollment_id in ^arg(:enrollment_ids))
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :amount, :integer, allow_nil?: false, public?: true
    attribute :reason, :string, allow_nil?: false, public?: true
    attribute :recorded_by_user_id, :uuid, allow_nil?: true, public?: true

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
  end

  identities do
    identity :unique_adjustment, [:enrollment_id]
  end
end
