defmodule TeacherAssistant.Academics.AcademicYear do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "academic_years"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:name, :start_date, :end_date, :active, :personal_workspace_id],
      update: [:name, :start_date, :end_date, :active]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :start_date, :date, allow_nil?: false, public?: true
    attribute :end_date, :date, allow_nil?: false, public?: true
    attribute :active, :boolean, default: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :personal_workspace, TeacherAssistant.Academics.PersonalWorkspace do
      source_attribute :personal_workspace_id
      allow_nil? false
      public? true
    end

    has_many :terms, TeacherAssistant.Academics.Term
  end

  identities do
    identity :unique_workspace_year, [:personal_workspace_id, :name]
  end
end
