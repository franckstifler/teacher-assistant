defmodule TeacherAssistant.Academics.ProgressionPlan do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "progression_plans"
    repo TeacherAssistant.Repo

    references do
      reference :combined_course, on_delete: :nilify
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :title,
        :status,
        :template,
        :teaching_context_id,
        :combined_course_id,
        :academic_year_id,
        :workspace_id
      ],
      update: [:title, :status, :template]
    ]

    # One plan per teaching *unit* in a workspace: course plans, plus the plans
    # of contexts that are NOT part of a combined course. Drops a member
    # context's stale solo plan (created before the context was combined) so a
    # `CombinedCourse` surfaces exactly one coverage KPI instead of one per
    # member class. A course plan has no `teaching_context_id`; a lone-context
    # plan's `teaching_context.combined_course_id` is nil — either keeps it.
    read :unit_plans do
      argument :workspace_id, :uuid, allow_nil?: false

      filter expr(
               workspace_id == ^arg(:workspace_id) and
                 (is_nil(teaching_context_id) or is_nil(teaching_context.combined_course_id))
             )

      prepare build(sort: [inserted_at: :desc])
    end

    # Every plan in the workspace, raw (includes a combined member's stale
    # pre-combine plan — teacher-facing call sites should prefer
    # `:unit_plans`). Mirrors the old `Academics.list_progression_plans/1`.
    read :for_workspace do
      argument :workspace_id, :uuid, allow_nil?: false
      filter expr(workspace_id == ^arg(:workspace_id))
      prepare build(sort: [inserted_at: :desc])
    end

    # Owner-scoped single-plan lookup (IDOR guard): the plan must belong to
    # the given workspace. Backs `Curriculum.fetch_owned_plan/2`.
    read :owned do
      argument :id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and workspace_id == ^arg(:workspace_id))
    end

    # Creates a plan owned by a `CombinedCourse` rather than a lone
    # `TeachingContext` — the course delivers one set of lessons, so it owns
    # one plan. Defaults `academic_year_id` from the course and `title` from
    # the course's subject when the caller doesn't supply them (mirrors the
    # old `Academics.create_course_plan/2`'s `Map.put_new/3` behavior).
    create :for_course do
      accept [:title, :status, :template]

      argument :course, :struct,
        allow_nil?: false,
        constraints: [instance_of: TeacherAssistant.Academics.CombinedCourse]

      change fn changeset, _context ->
        course = Ash.Changeset.get_argument(changeset, :course)

        changeset
        |> Ash.Changeset.force_change_attribute(:combined_course_id, course.id)
        |> Ash.Changeset.force_change_attribute(:workspace_id, course.workspace_id)
        |> then(fn changeset ->
          if Ash.Changeset.changing_attribute?(changeset, :academic_year_id) do
            changeset
          else
            Ash.Changeset.change_attribute(changeset, :academic_year_id, course.academic_year_id)
          end
        end)
        |> then(fn changeset ->
          if Ash.Changeset.changing_attribute?(changeset, :title) do
            changeset
          else
            Ash.Changeset.change_attribute(changeset, :title, course.subject)
          end
        end)
      end
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  validations do
    validate TeacherAssistant.Academics.ProgressionPlan.ExactlyOneOwner, on: [:create]
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true

    attribute :status, :atom,
      constraints: [one_of: [:draft, :active]],
      default: :draft,
      public?: true

    attribute :template, :boolean, allow_nil?: false, default: false, public?: true
    attribute :combined_course_id, :uuid, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? true
      public? true
    end

    belongs_to :combined_course, TeacherAssistant.Academics.CombinedCourse do
      source_attribute :combined_course_id
      define_attribute? false
      allow_nil? true
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

    has_many :entries, TeacherAssistant.Academics.ProgressionEntry
  end
end
