defmodule TeacherAssistant.Academics.Payment do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "payments"
    repo TeacherAssistant.Repo

    references do
      reference :enrollment, on_delete: :delete
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
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :enrollment, TeacherAssistant.Academics.Enrollment do
      source_attribute :enrollment_id
      allow_nil? false
      public? true
    end
  end
end
