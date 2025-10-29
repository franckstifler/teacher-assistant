defmodule TeacherAssistant.Academics.AcademicYear do
  use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: TeacherAssistant.Academics

  postgres do
    repo TeacherAssistant.Repo
    table "academic_years"
  end

  actions do
    default_accept [:name, :description, :start_date, :end_date, :active]
    defaults [:read, :destroy]

    create :create do
      primary? true
      argument :terms, {:array, :map}, allow_nil?: false, constraints: [min: 1]

      change manage_relationship(:terms, :terms, type: :direct_control, order_is_key: :position)
    end

    update :update do
      primary? true
      require_atomic? false
      argument :terms, {:array, :map}, allow_nil?: false, constraints: [min: 1]

      change manage_relationship(:terms, :terms, type: :direct_control, order_is_key: :position)
    end

    read :get_active_year do
      get? true
      filter expr(active == true)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :start_date, :date, allow_nil?: false, public?: true
    attribute :end_date, :date, allow_nil?: false, public?: true
    attribute :active, :boolean, default: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    has_many :terms, TeacherAssistant.Academics.Term
  end

  identities do
    identity :unique_name, [:name]
  end
end
