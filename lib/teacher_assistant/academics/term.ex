defmodule TeacherAssistant.Academics.Term do
  use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: TeacherAssistant.Academics

  postgres do
    repo TeacherAssistant.Repo
    table "terms"
  end

  actions do
    default_accept [:name, :start_date, :end_date]
    defaults [:read, :destroy]

    create :create do
      primary? true
      argument :sequences, {:array, :map}, default: [], allow_nil?: false, constraints: [min: 1]
      change manage_relationship(:sequences, :sequences, type: :direct_control)
    end

    update :update do
      primary? true
      require_atomic? false
      argument :sequences, {:array, :map}, default: [], allow_nil?: false, constraints: [min: 1]
      change manage_relationship(:sequences, :sequences, type: :direct_control)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :start_date, :date, public?: true
    attribute :end_date, :date, public?: true
    attribute :position, :integer

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear, allow_nil?: false
    has_many :sequences, TeacherAssistant.Academics.Sequence
  end

  identities do
    identity :name, [:name]
  end
end
