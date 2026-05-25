defmodule TeacherAssistant.Academics.ClassroomStudent do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "classrooms_students"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    update :set_access_status do
      require_atomic? false
      accept [:access_status, :access_note, :access_set_by_id]

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :access_set_at, DateTime.utc_now())
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action(:set_access_status) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:role, :accountant)
      authorize_if actor_attribute_equals(:role, :principal)
    end

    policy action([:create, :update, :destroy]) do
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

    attribute :access_status, TeacherAssistant.Academics.Enums.EnrollmentAccessStatus,
      public?: true,
      allow_nil?: false,
      default: :allowed

    attribute :access_note, :string, public?: true
    attribute :access_set_at, :utc_datetime_usec, public?: true
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :classroom, TeacherAssistant.Academics.Classroom, allow_nil?: false, public?: true
    belongs_to :student, TeacherAssistant.Academics.Student, allow_nil?: false, public?: true

    belongs_to :access_set_by, TeacherAssistant.Accounts.User do
      source_attribute :access_set_by_id
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :classroom_student, [:classroom_id, :student_id]
  end
end
