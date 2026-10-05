defmodule TeacherAssistant.Academics.Student do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Enrollment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "students"
    repo TeacherAssistant.Repo

    custom_indexes do
      index [:workspace_id, :matricule],
        unique: true,
        where: "matricule IS NOT NULL",
        name: "students_unique_matricule_index",
        message: "matricule already used in this workspace"

      # Composite-FK target: attribute multitenancy prefixes this to
      # (workspace_id, id), the unique key that tenant-matched references need.
      index [:id], unique: true
    end

    references do
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:full_name, :sex, :matricule, :birth_date, :birth_place],
      update: [:full_name, :sex, :matricule, :birth_date, :birth_place]
    ]

    read :owned do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    read :by_matricule do
      argument :matricule, :string, allow_nil?: false
      filter expr(matricule == ^arg(:matricule))
    end

    read :search_by_name do
      argument :query, :string, allow_nil?: false

      filter expr(contains(string_downcase(full_name), ^arg(:query)))

      prepare build(sort: [full_name: :asc], limit: 10)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end

    policy action_type(:update) do
      # Row rules name a user, not a membership: require an active one.
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
      authorize_if expr(exists(enrollments, class_group.form_master_user_id == ^actor(:id)))
    end
  end

  validations do
    validate compare(:birth_date, less_than_or_equal_to: &Date.utc_today/0),
      where: [present(:birth_date)],
      message: "la date de naissance ne peut pas être dans le futur"
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :full_name, :string, allow_nil?: false, public?: true
    attribute :sex, TeacherAssistant.Academics.Sex, allow_nil?: false, public?: true
    attribute :matricule, :string, allow_nil?: true, public?: true
    attribute :birth_date, :date, allow_nil?: true, public?: true

    attribute :birth_place, :string,
      allow_nil?: true,
      public?: true,
      constraints: [max_length: 120]

    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    has_many :enrollments, TeacherAssistant.Academics.Enrollment
    has_many :guardian_links, TeacherAssistant.Academics.StudentGuardian

    has_one :primary_guardian_link, TeacherAssistant.Academics.StudentGuardian do
      filter expr(primary_contact == true)
    end
  end
end
