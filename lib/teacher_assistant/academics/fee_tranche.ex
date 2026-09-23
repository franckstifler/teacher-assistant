defmodule TeacherAssistant.Academics.FeeTranche do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Fees,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "fee_tranches"
    repo TeacherAssistant.Repo

    references do
      reference :class_group, on_delete: :delete, index?: true
      reference :workspace, on_delete: :delete, index?: true
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
        :workspace_id,
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
    policy always() do
      authorize_if always()
    end
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
