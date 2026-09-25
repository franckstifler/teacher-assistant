defmodule TeacherAssistant.Academics.ClassGroup do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Enrollment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "class_groups"
    repo TeacherAssistant.Repo

    custom_indexes do
      # Composite-FK target: attribute multitenancy prefixes this to
      # (workspace_id, id), the unique key that tenant-matched references need.
      index [:id], unique: true
    end

    references do
      reference :form_master, on_delete: :nilify, index?: true

      reference :academic_year,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:label, :level, :serie, :subsystem, :academic_year_id],
      update: [:label, :level, :serie, :subsystem, :form_master_user_id]
    ]

    read :for_workspace_and_year do
      argument :academic_year_id, :uuid, allow_nil?: false

      filter expr(academic_year_id == ^arg(:academic_year_id))

      prepare build(sort: [label: :asc])
    end

    read :owned do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
    end

    read :for_form_master do
      argument :academic_year_id, :uuid, allow_nil?: false
      argument :form_master_user_id, :uuid, allow_nil?: false

      filter expr(
               academic_year_id == ^arg(:academic_year_id) and
                 form_master_user_id == ^arg(:form_master_user_id)
             )

      prepare build(sort: [label: :asc])
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
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
      allow_nil? true
      public? true
    end

    has_many :enrollments, TeacherAssistant.Academics.Enrollment
  end

  identities do
    identity :unique_class_group, [:workspace_id, :academic_year_id, :label]
  end
end
