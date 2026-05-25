defmodule TeacherAssistant.Academics.GradeInterval do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "grade_intervals"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [:min_score, :max_score, :label, :appreciation, :position]
    defaults [:create, :read, :update, :destroy]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action_type([:create, :update, :destroy]) do
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

    attribute :min_score, :decimal,
      public?: true,
      allow_nil?: false,
      constraints: [min: Decimal.new("0"), max: Decimal.new("20")]

    attribute :max_score, :decimal,
      public?: true,
      allow_nil?: false,
      constraints: [min: Decimal.new("0"), max: Decimal.new("20")]

    attribute :label, :string, public?: true, allow_nil?: false
    attribute :appreciation, :string, public?: true, allow_nil?: false
    attribute :position, :integer, public?: true, default: 0

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
  end
end
