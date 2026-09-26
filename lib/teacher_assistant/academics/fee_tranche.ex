defmodule TeacherAssistant.Academics.FeeTranche do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Fees,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "fee_tranches"
    repo TeacherAssistant.Repo

    references do
      reference :class_group,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end

    # >= 0, not > 0: `Fees.add_tranche/2`'s own `validate_amount/1` guard
    # already treats a zero-amount tranche as valid (see
    # `FeeTrancheTest."amount accepts 0"`) — this is the DB-level backstop
    # for that same rule, not a stricter one.
    check_constraints do
      check_constraint :amount, "fee_tranches_amount_non_negative_check",
        check: "amount >= 0",
        message: "must not be negative"
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :label,
        :amount,
        :due_date,
        :position,
        :class_group_id
      ],
      update: [
        :label,
        :amount,
        :due_date,
        :position
      ]
    ]

    read :for_class_group do
      argument :class_group_id, :uuid, allow_nil?: false

      filter expr(class_group_id == ^arg(:class_group_id))

      prepare build(sort: [position: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      # Row rules name a user, not a membership: require an active one.
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :fees}
      authorize_if expr(class_group.form_master_user_id == ^actor(:id))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :fees}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :label, :string, allow_nil?: false, public?: true
    attribute :amount, :integer, allow_nil?: false, public?: true
    attribute :due_date, :date, allow_nil?: false, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end
end
