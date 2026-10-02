defmodule TeacherAssistant.Academics.Guardian do
  @moduledoc """
  Spec KLM1 (M2): a parent or guardian of one or more students of the school.
  Shared by siblings through `StudentGuardian`; no login.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Enrollment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks
  alias TeacherAssistant.Academics.Guardian.Changes.PhoneKey

  postgres do
    table "guardians"
    repo TeacherAssistant.Repo

    custom_indexes do
      # Composite-FK target, as on every tenant resource.
      index [:id], unique: true
      index [:workspace_id, :phone_key]
    end

    references do
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:full_name, :relationship, :phone, :phone_2, :email, :language]
      change PhoneKey
    end

    update :update do
      primary? true
      accept [:full_name, :relationship, :phone, :phone_2, :email, :language]
      change PhoneKey
    end

    read :by_phone_key do
      argument :phone_key, :string, allow_nil?: false
      filter expr(phone_key == ^arg(:phone_key))
      prepare build(sort: [full_name: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
      authorize_if expr(exists(student_links.student.enrollments, class_group.form_master_user_id == ^actor(:id)))

      authorize_if expr(
                     exists(
                       student_links.student.enrollments.class_group.teaching_contexts,
                       teacher_user_id == ^actor(:id)
                     )
                   )
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :full_name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 120]

    attribute :relationship, TeacherAssistant.Academics.GuardianRelationship,
      allow_nil?: false,
      public?: true

    attribute :phone, :string, allow_nil?: false, public?: true, constraints: [max_length: 30]
    attribute :phone_key, :string, allow_nil?: false
    attribute :phone_2, :string, public?: true, constraints: [max_length: 30]
    attribute :email, :ci_string, public?: true

    attribute :language, TeacherAssistant.Academics.ContactLanguage,
      allow_nil?: false,
      default: :fr,
      public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    has_many :student_links, TeacherAssistant.Academics.StudentGuardian
  end
end
