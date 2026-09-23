defmodule TeacherAssistant.Academics.Payment do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Fees,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "payments"
    repo TeacherAssistant.Repo

    references do
      reference :enrollment, on_delete: :delete, index?: true
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :amount,
        :paid_on,
        :method,
        :reference,
        :note,
        :recorded_by_user_id,
        :workspace_id,
        :enrollment_id
      ],
      update: [
        :amount,
        :paid_on,
        :method,
        :reference,
        :note,
        :recorded_by_user_id
      ]
    ]

    read :for_enrollment do
      argument :enrollment_id, :uuid, allow_nil?: false

      filter expr(enrollment_id == ^arg(:enrollment_id))

      prepare build(sort: [paid_on: :desc, inserted_at: :desc])
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
end
