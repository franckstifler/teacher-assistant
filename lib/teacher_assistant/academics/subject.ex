defmodule TeacherAssistant.Academics.Subject do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "subjects"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [:name, :description, :default_coefficient]
    defaults [:create, :update, :read, :destroy]

    read :list_teacher_subjects do
      argument :year_id, :uuid_v7, allow_nil?: false

      filter expr(
               #  school_year_subject_teacher.teacher_id == ^actor(:id) and
               level_option_subjects.teaching_assignments.classroom.academic_year_id ==
                 ^arg(:year_id)
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

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :description, :string, public?: true
    attribute :default_coefficient, :integer, public?: true, default: 1, constraints: [min: 1]

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School

    has_many :level_option_subjects, TeacherAssistant.Academics.LevelOptionSubject

    many_to_many :levels_options, TeacherAssistant.Academics.LevelOption do
      through TeacherAssistant.Academics.LevelOptionSubject
      source_attribute_on_join_resource :subject_id
      destination_attribute_on_join_resource :level_option_id
    end
  end

  identities do
    identity :unique_name, [:school_id, :name]
  end
end
