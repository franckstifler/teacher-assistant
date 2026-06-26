defmodule TeacherAssistant.Academics.PersonalClassroom do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "personal_classrooms"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:class_label, :subject, :personal_workspace_id, :academic_year_id],
      update: [:class_label, :subject]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :class_label, :string, allow_nil?: false, public?: true
    attribute :subject, :string, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :personal_workspace, TeacherAssistant.Academics.PersonalWorkspace do
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      allow_nil? false
      public? true
    end

    has_many :learners, TeacherAssistant.Academics.Learner
    has_many :attendance_sessions, TeacherAssistant.Academics.AttendanceSession
    has_many :lesson_plan_entries, TeacherAssistant.Academics.LessonPlanEntry
  end

  identities do
    identity :unique_workspace_class_subject_year,
             [:personal_workspace_id, :academic_year_id, :class_label, :subject]
  end
end
