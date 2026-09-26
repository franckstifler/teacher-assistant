defmodule TeacherAssistant.Academics.ProgressionEntry do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "progression_entries"
    repo TeacherAssistant.Repo

    custom_indexes do
      index [:progression_module_id, :position]

      # Composite-FK target: attribute multitenancy prefixes this to
      # (workspace_id, id), the unique key that tenant-matched references need.
      index [:id], unique: true
    end

    references do
      reference :progression_plan,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :sequence,
        match_with: [workspace_id: :workspace_id],
        match_type: :simple,
        index?: true

      reference :progression_module,
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
        :progression_module_id,
        :lesson_title,
        :planned_hours,
        :entry_type,
        :week_no,
        :position,
        :famille_de_situations,
        :categories_action,
        :competence_visee,
        :progression_plan_id,
        :sequence_id,
        :completed?
      ],
      update: [
        :progression_module_id,
        :lesson_title,
        :planned_hours,
        :entry_type,
        :week_no,
        :position,
        :famille_de_situations,
        :categories_action,
        :competence_visee,
        :sequence_id,
        :completed?
      ]
    ]

    # All entries of a plan, in position order, with their module preloaded.
    # Mirrors the old `Academics.list_progression_entries/1`.
    read :for_plan do
      argument :progression_plan_id, :uuid, allow_nil?: false
      filter expr(progression_plan_id == ^arg(:progression_plan_id))
      prepare build(sort: [position: :asc], load: [:progression_module])
    end

    # Owner-scoped single-entry lookup (IDOR guard): tenant scoping (attribute
    # multitenancy) already restricts this to the given workspace. Backs
    # `Curriculum.fetch_owned_entry/2`.
    read :owned do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update, :destroy]) do
      # Row rules name a user, not a membership: require an active one.
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if expr(progression_plan.teaching_context.teacher_user_id == ^actor(:id))

      authorize_if expr(
                     exists(
                       progression_plan.combined_course.teaching_contexts,
                       teacher_user_id == ^actor(:id)
                     )
                   )
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :lesson_title, :string, allow_nil?: false, public?: true
    attribute :planned_hours, :decimal, default: Decimal.new("1"), public?: true

    attribute :entry_type, TeacherAssistant.Academics.ProgressionEntryType,
      allow_nil?: false,
      default: :lesson,
      public?: true

    attribute :week_no, :integer, allow_nil?: true, public?: true
    attribute :completed?, :boolean, allow_nil?: false, default: false, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :famille_de_situations, :string, allow_nil?: true, public?: true
    attribute :categories_action, :string, allow_nil?: true, public?: true
    attribute :competence_visee, :string, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :progression_plan, TeacherAssistant.Academics.ProgressionPlan do
      source_attribute :progression_plan_id
      allow_nil? false
      public? true
    end

    belongs_to :sequence, TeacherAssistant.Academics.Sequence do
      source_attribute :sequence_id
      allow_nil? true
      public? true
    end

    belongs_to :progression_module, TeacherAssistant.Academics.ProgressionModule do
      source_attribute :progression_module_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end
end
