defmodule TeacherAssistant.Academics.StudentGuardian do
  @moduledoc """
  Spec KLM1 (M2): a guardian of a student. At most one link per student is the
  main contact (`primary_contact`), enforced by a partial unique index; the
  first link becomes primary; unlinking the last link of a guardian deletes it.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Enrollment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks
  alias TeacherAssistant.Academics.StudentGuardian.Changes

  postgres do
    table "student_guardians"
    repo TeacherAssistant.Repo

    custom_indexes do
      index [:id], unique: true

      index [:workspace_id, :student_id],
        unique: true,
        where: "primary_contact",
        name: "student_guardians_one_primary_index",
        message: "a student has only one main contact"
    end

    references do
      reference :student,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :guardian,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read, :destroy, create: [:student_id, :guardian_id, :primary_contact]]

    read :for_student do
      argument :student_id, :uuid, allow_nil?: false
      filter expr(student_id == ^arg(:student_id))
      prepare build(load: [:guardian], sort: [primary_contact: :desc, inserted_at: :asc])
    end

    create :link do
      accept [:student_id, :guardian_id]
      change Changes.PrimaryIfFirst
    end

    update :make_primary do
      require_atomic? false
      change Changes.UnsetOtherPrimaries
      change set_attribute(:primary_contact, true)
    end

    # Internal: used by `make_primary` to clear the previous main contact.
    update :unset_primary do
      change set_attribute(:primary_contact, false)
    end

    destroy :unlink do
      require_atomic? false
      change Changes.DeleteOrphanGuardian
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
      authorize_if expr(exists(student.enrollments, class_group.form_master_user_id == ^actor(:id)))

      authorize_if expr(
                     exists(
                       student.enrollments.class_group.teaching_contexts,
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
    attribute :primary_contact, :boolean, allow_nil?: false, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :student, TeacherAssistant.Academics.Student do
      source_attribute :student_id
      allow_nil? false
      public? true
    end

    belongs_to :guardian, TeacherAssistant.Academics.Guardian do
      source_attribute :guardian_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_link, [:student_id, :guardian_id]
  end
end
