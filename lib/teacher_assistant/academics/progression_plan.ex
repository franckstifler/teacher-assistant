defmodule TeacherAssistant.Academics.ProgressionPlan do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "progression_plans"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:title, :status, :template, :teaching_context_id, :academic_year_id, :personal_workspace_id],
      update: [:title, :status, :template]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :status, :atom, constraints: [one_of: [:draft, :active]], default: :draft, public?: true
    attribute :template, :boolean, allow_nil?: false, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    belongs_to :personal_workspace, TeacherAssistant.Academics.PersonalWorkspace do
      source_attribute :personal_workspace_id
      allow_nil? false
      public? true
    end
  end
end
