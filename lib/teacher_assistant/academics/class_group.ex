defmodule TeacherAssistant.Academics.ClassGroup do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "class_groups"
    repo TeacherAssistant.Repo

    references do
      reference :form_master, on_delete: :nilify
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:label, :level, :serie, :subsystem, :workspace_id, :academic_year_id],
      update: [:label, :level, :serie, :subsystem, :form_master_user_id]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :label, :string, allow_nil?: false, public?: true
    attribute :level, :string, allow_nil?: false, public?: true
    attribute :serie, :string, allow_nil?: true, public?: true

    attribute :subsystem, TeacherAssistant.Academics.Subsystem,
      allow_nil?: false,
      default: :francophone,
      public?: true

    attribute :form_master_user_id, :uuid, allow_nil?: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    belongs_to :form_master, TeacherAssistant.Accounts.User do
      source_attribute :form_master_user_id
      define_attribute? false
      allow_nil? true
      public? true
    end

    has_many :enrollments, TeacherAssistant.Academics.Enrollment
  end

  identities do
    identity :unique_class_group, [:workspace_id, :academic_year_id, :label]
  end
end
