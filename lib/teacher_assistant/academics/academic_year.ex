defmodule TeacherAssistant.Academics.AcademicYear do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource]

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

    update :manage_classrooms do
      require_atomic? false
      accept []
      argument :levels_options, {:array, :uuid_v7}, default: []

      change manage_relationship(:levels_options, :classrooms, type: :append_and_remove)
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

    has_many :terms, TeacherAssistant.Academics.Term do
      sort position: :asc
    end

    many_to_many :classrooms, TeacherAssistant.Academics.LevelOption do
      through TeacherAssistant.Academics.Classroom
      source_attribute_on_join_resource :academic_year_id
      destination_attribute_on_join_resource :level_option_id
    end
  end

  identities do
    identity :unique_name, [:school_id, :name]
  end
end
