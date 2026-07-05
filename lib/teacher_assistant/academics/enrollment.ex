defmodule TeacherAssistant.Academics.Enrollment do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "enrollments"
    repo TeacherAssistant.Repo

    references do
      reference :student, on_delete: :delete
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :status,
        :repeater,
        :student_id,
        :class_group_id,
        :academic_year_id,
        :workspace_id
      ],
      update: [:status, :repeater, :class_group_id]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :status, TeacherAssistant.Academics.EnrollmentStatus,
      allow_nil?: false,
      default: :inscription,
      public?: true

    attribute :repeater, :boolean, allow_nil?: false, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :student, TeacherAssistant.Academics.Student do
      source_attribute :student_id
      allow_nil? false
      public? true
    end

    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_enrollment_per_year, [:student_id, :academic_year_id]
  end
end
