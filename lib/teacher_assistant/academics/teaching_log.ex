defmodule TeacherAssistant.Academics.TeachingLog do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "teaching_logs"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [:progression_entry_id, :taught_on, :taught_hours, :notes]
    defaults [:create, :read, :update, :destroy]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action_type([:create, :update]) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :teacher)
      authorize_if actor_attribute_equals(:role, :principal_teacher)
    end

    policy action_type(:destroy) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :principal)
      authorize_if actor_attribute_equals(:role, :vice_principal)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :taught_on, :date, public?: true, allow_nil?: false
    attribute :taught_hours, :decimal, public?: true, allow_nil?: false, default: Decimal.new("0")
    attribute :notes, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :progression_entry, TeacherAssistant.Academics.ProgressionEntry, allow_nil?: false
  end
end
