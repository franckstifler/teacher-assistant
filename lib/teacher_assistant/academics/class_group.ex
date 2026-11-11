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

      reference :home_room,
        on_delete: {:nilify, [:home_room_id]},
        match_with: [workspace_id: :workspace_id],
        match_type: :simple,
        index?: true

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
        :form_master_user_id,
        :home_room_id
      ],
      update: [
        :label,
        :level,
        :serie,
        :subsystem,
        :form_master_user_id,
        :max_size,
        :home_room_id
      ]
    ]

    # Paper roll call (spec 2026-10-28 §1): conduct managers switch it too.
    update :set_paper_roll_call do
      accept [:paper_roll_call]
      # `YearOpen` reads the record's year, so no atomic (single statement) update.
      require_atomic? false
    end

    # Spec 2026-10-30 §1: where the bulletin's absence hours come from.
    update :set_absence_hours_source do
      accept [:absence_hours_source]
      require_atomic? false
    end

    # Spec 2026-10-29: the « Photos examen » page saves them; conduct managers too.
    update :set_exam_codes do
      accept [:exam_code, :exam_center_code]
      require_atomic? false
    end

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

    policy action([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end

    policy action([:set_paper_roll_call, :set_absence_hours_source, :set_exam_codes]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
    end
  end

  changes do
    change {TeacherAssistant.Academics.YearOpen, path: []}, on: [:create, :update, :destroy]
  end

  validations do
    # Only when the form master is set: a class whose form master has since left the
    # school must still take its other changes (exam codes, paper roll call…).
    validate TeacherAssistant.Academics.ClassGroup.FormMasterIsMember,
      on: [:create, :update],
      where: [changing(:form_master_user_id)]
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

    # Spec 2026-10-28: the roll call is taken on a weekly printed sheet, typed in by the
    # surveillant; untaken lessons wait for it instead of counting as missed.
    attribute :paper_roll_call, :boolean, allow_nil?: false, default: true, public?: true

    attribute :absence_hours_source, TeacherAssistant.Academics.AbsenceHoursSource,
      allow_nil?: false,
      default: :roll_call,
      public?: true

    # Spec 2026-10-29: the codes printed on the candidates' exam pictures (one exam code
    # for the whole class, the « CR » code typed by the school).
    attribute :exam_code, :string, allow_nil?: true, public?: true
    attribute :exam_center_code, :string, allow_nil?: true, public?: true

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

    # Spec J3: the class's own room; nil = none set.
    belongs_to :home_room, TeacherAssistant.Academics.Room do
      source_attribute :home_room_id
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
    # A7: the class today, without the students who left.
    count :enrollment_count, :enrollments do
      filter expr(is_nil(left_on))
    end
  end

  identities do
    identity :unique_class_group, [:workspace_id, :academic_year_id, :label]
  end
end
