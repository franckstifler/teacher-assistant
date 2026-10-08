defmodule TeacherAssistant.Academics.ClassGroup do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Enrollment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

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
      create: [
        :label,
        :level,
        :serie,
        :subsystem,
        :academic_year_id,
        :max_size,
        :form_master_user_id
      ],
      update: [:label, :level, :serie, :subsystem, :form_master_user_id, :max_size]
    ]

    read :for_workspace_and_year do
      argument :academic_year_id, :uuid, allow_nil?: false

      filter expr(academic_year_id == ^arg(:academic_year_id))

      prepare build(sort: [level_rank: :asc, label: :asc])
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
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  validations do
    validate {TeacherAssistant.Academics.YearOpen, path: []}, on: [:create, :update, :destroy]
    validate TeacherAssistant.Academics.ClassGroup.FormMasterIsMember, on: [:create, :update]
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

    # Spec 2026-10-08 §1: overrides the school's max_class_size; a warning, never a block.
    attribute :max_size, :integer,
      allow_nil?: true,
      public?: true,
      constraints: [min: 1, max: 200]

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
    has_many :teaching_contexts, TeacherAssistant.Academics.TeachingContext
  end

  calculations do
    # Position of `level` in the school ladder (6ème first); unknown levels last.
    calculate :level_rank,
              :integer,
              expr(
                fragment(
                  "coalesce(array_position(?::text[], ?), 1000)",
                  ^TeacherAssistant.Academics.SchoolTemplates.level_order(),
                  level
                )
              )
  end

  aggregates do
    # Spec KLM5 (R05): one query for every class's headcount.
    count :enrollment_count, :enrollments
  end

  identities do
    identity :unique_class_group, [:workspace_id, :academic_year_id, :label]
  end
end
