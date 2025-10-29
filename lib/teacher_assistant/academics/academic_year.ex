defmodule TeacherAssitant.Academics.AcademicYear do
  use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: TeacherAssitant.Academics

  postgres do
    repo TeacherAssitant.Repo
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
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :start_date, :date, allow_nil?: false, public?: true
    attribute :end_date, :date, allow_nil?: false, public?: true
    attribute :active, :boolean, default: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssitant.Academics.School
    has_many :terms, TeacherAssitant.Academics.Term
  end

  identities do
    identity :unique_name, [:name]
    identity :unique_active, [:active], where: expr(active == true)
  end
end
