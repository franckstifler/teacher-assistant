defmodule TeacherAssistant.Academics.TeachingContext do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "teaching_contexts"
    repo TeacherAssistant.Repo

    custom_indexes do
      index [:workspace_id, :academic_year_id, :class_group_id, :subject],
        unique: true,
        name: "teaching_contexts_unique_school_assignment",
        message: "this class already has a teacher for this subject"

      # Composite-FK target: attribute multitenancy prefixes this to
      # (workspace_id, id), the unique key that tenant-matched references need.
      index [:id], unique: true
    end

    references do
      reference :combined_course,
        on_delete: {:nilify, [:combined_course_id]},
        match_with: [workspace_id: :workspace_id],
        match_type: :simple,
        index?: true

      reference :workspace, on_delete: :delete, index?: true

      reference :academic_year,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :class_group,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :teacher, index?: true

      reference :catalog_subject,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :subject,
        :subject_id,
        :level,
        :serie,
        :subsystem,
        :weekly_hours,
        :coefficient,
        :academic_year_id,
        :teacher_user_id,
        :class_group_id
      ],
      update: [
        :subject,
        :subject_id,
        :level,
        :serie,
        :subsystem,
        :weekly_hours,
        :coefficient,
        :class_group_id,
        :teacher_user_id,
        :combined_course_id
      ]
    ]

    read :for_class_group do
      argument :class_group_id, :uuid, allow_nil?: false
      filter expr(class_group_id == ^arg(:class_group_id))
      prepare build(
                load: [
                  :teacher,
                  :combined_course,
                  :catalog_subject,
                  :grid_coefficient,
                  :effective_coefficient,
                  :taught_here?
                ],
                sort: [subject: :asc]
              )
    end

    # Owner-scoped single-context lookup (IDOR guard): tenant scoping
    # (attribute multitenancy) already restricts this to the given workspace.
    # Backs `Curriculum.fetch_owned_teaching_context/2`.
    read :owned do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    # School-scoped single-context lookup: tenant scoping already restricts
    # this to the workspace; the context must additionally be assigned to the
    # given teacher (a colleague may not open another teacher's roster by
    # id). Backs the school clause of `Curriculum.fetch_assigned_teaching_context/2`.
    read :assigned_in_school do
      argument :id, :uuid, allow_nil?: false
      argument :teacher_user_id, :uuid, allow_nil?: false

      filter expr(id == ^arg(:id) and teacher_user_id == ^arg(:teacher_user_id))
    end

    read :for_combined_course do
      argument :combined_course_id, :uuid, allow_nil?: false
      filter expr(combined_course_id == ^arg(:combined_course_id))
    end

    read :for_workspace_year_teacher do
      argument :academic_year_id, :uuid, allow_nil?: false
      argument :teacher_user_id, :uuid, allow_nil?: false

      filter expr(
               academic_year_id == ^arg(:academic_year_id) and
                 teacher_user_id == ^arg(:teacher_user_id)
             )

      prepare build(load: [:class_group], sort: [subject: :asc])
    end

    read :combinable_siblings do
      argument :academic_year_id, :uuid, allow_nil?: false
      argument :subject, :string, allow_nil?: false
      argument :teacher_user_id, :uuid, allow_nil?: true
      argument :exclude_id, :uuid, allow_nil?: false

      filter expr(
               academic_year_id == ^arg(:academic_year_id) and
                 subject == ^arg(:subject) and
                 teacher_user_id == ^arg(:teacher_user_id) and
                 is_nil(combined_course_id) and
                 id != ^arg(:exclude_id)
             )

      prepare build(load: [:class_group], sort: [subject: :asc])
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

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :subject, :string, allow_nil?: false, public?: true
    attribute :level, :string, allow_nil?: false, public?: true
    attribute :serie, :string, allow_nil?: true, public?: true

    attribute :subsystem, TeacherAssistant.Academics.Subsystem,
      allow_nil?: false,
      default: :francophone,
      public?: true

    attribute :weekly_hours, :integer, default: 4, public?: true

    # The class override. nil = the coefficient grid (see `effective_coefficient`).
    attribute :coefficient, :decimal, allow_nil?: true, public?: true

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

    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end

    belongs_to :teacher, TeacherAssistant.Accounts.User do
      source_attribute :teacher_user_id
      allow_nil? false
      public? true
    end

    belongs_to :combined_course, TeacherAssistant.Academics.CombinedCourse do
      source_attribute :combined_course_id
      allow_nil? true
      public? true
    end

    belongs_to :catalog_subject, TeacherAssistant.Academics.Subject do
      source_attribute :subject_id
      allow_nil? false
      public? true
    end

    # The grid cell this assignment resolves to: its série's cell, else the
    # blank-série cell of its level (same rule as `CoefficientRules.resolve/2`).
    has_one :grid_coefficient, TeacherAssistant.Academics.SubjectCoefficient do
      no_attributes? true
      from_many? true
      public? true

      filter expr(
               subject_id == parent(subject_id) and subsystem == parent(subsystem) and
                 level == parent(level) and (serie == parent(serie) or is_nil(serie))
             )

      sort serie: :asc_nils_last
    end
  end

  calculations do
    calculate :effective_coefficient,
              :decimal,
              expr(coefficient || grid_coefficient.coefficient || catalog_subject.default_coefficient) do
      public? true
    end

    calculate :taught_here?, :boolean, expr(not is_nil(grid_coefficient.id)) do
      public? true
    end
  end
end
