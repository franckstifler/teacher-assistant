defmodule TeacherAssistant.Academics.Classroom do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "classrooms"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:academic_year_id, :level_option_id]
    end

    update :update do
      primary? true
      accept [:academic_year_id, :level_option_id]
    end

    read :list_teacher_classrooms do
      argument :academic_year_id, :uuid_v7, allow_nil?: false
      argument :teacher_id, :uuid_v7, allow_nil?: false

      filter expr(
               teaching_assignments.teacher_id == ^arg(:teacher_id) and
                 academic_year_id == ^arg(:academic_year_id)
             )
    end
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
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear, allow_nil?: false
    belongs_to :level_option, TeacherAssistant.Academics.LevelOption, allow_nil?: false
    has_many :teaching_assignments, TeacherAssistant.Academics.TeachingAssignment
  end

  identities do
    identity :name, [:academic_year_id, :level_option_id]
  end
end
