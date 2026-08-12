defmodule TeacherAssistant.Academics.ProgressionModule do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "progression_modules"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:title, :position, :progression_plan_id, :credit_hours],
      update: [:title, :position, :credit_hours]
    ]

    # System-only: creates the undeletable default bucket. `default?` is never
    # publicly accepted, so a teacher can never mint a second bucket.
    create :create_default_bucket do
      accept [:title, :position, :progression_plan_id]
      change set_attribute(:default?, true)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :default?, :boolean, allow_nil?: false, default: false, public?: true
    attribute :credit_hours, :decimal, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :progression_plan, TeacherAssistant.Academics.ProgressionPlan do
      source_attribute :progression_plan_id
      allow_nil? false
      public? true
    end

    has_many :entries, TeacherAssistant.Academics.ProgressionEntry
  end
end
