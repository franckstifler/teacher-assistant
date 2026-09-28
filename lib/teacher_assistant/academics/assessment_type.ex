defmodule TeacherAssistant.Academics.AssessmentType do
  @moduledoc """
  A school's kind of assessment (interrogation écrite, devoir surveillé…) and its default
  weight. The weight is copied onto an assessment when it is created, so changing a type
  never alters tests already given (spec D2b-2).
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "assessment_types"
    repo TeacherAssistant.Repo

    references do
      reference :workspace, on_delete: :delete, index?: true
    end

    custom_indexes do
      # Composite-FK target for `Assessment.assessment_type_id`.
      index [:id], unique: true
    end

    check_constraints do
      check_constraint :default_weight, "assessment_types_weight_positive_check",
        check: "default_weight > 0",
        message: "must be positive"
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:name, :default_weight, :position],
      update: [:name, :default_weight, :position]
    ]
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true, constraints: [trim?: true]
    attribute :default_weight, :decimal, allow_nil?: false, public?: true
    attribute :position, :integer, allow_nil?: false, default: 0, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    has_many :assessments, TeacherAssistant.Academics.Assessment
  end

  aggregates do
    count :usage_count, :assessments do
      public? true
    end
  end

  identities do
    identity :unique_type_name, [:workspace_id, :name]
  end
end
