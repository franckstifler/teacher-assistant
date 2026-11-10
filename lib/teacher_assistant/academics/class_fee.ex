defmodule TeacherAssistant.Academics.ClassFee do
  @moduledoc "What a class pays for one fee type in the year (Fees 1); none or 0 = not charged."
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Fees,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "class_fees"
    repo TeacherAssistant.Repo

    references do
      reference :class_group,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :fee_type,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end

    check_constraints do
      check_constraint :amount, "class_fees_amount_non_negative_check",
        check: "amount >= 0",
        message: "must not be negative"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :set do
      primary? true
      accept [:class_group_id, :fee_type_id, :amount]
      upsert? true
      upsert_identity :unique_class_fee
      upsert_fields [:amount]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :fees}
    end
  end

  changes do
    change {TeacherAssistant.Academics.YearOpen, path: [:class_group]},
      on: [:create, :update, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :amount, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end

    belongs_to :fee_type, TeacherAssistant.Academics.FeeType do
      source_attribute :fee_type_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_class_fee, [:class_group_id, :fee_type_id]
  end
end
