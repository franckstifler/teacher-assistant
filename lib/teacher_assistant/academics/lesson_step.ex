defmodule TeacherAssistant.Academics.LessonStep do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  require Ash.Query

  postgres do
    table "lesson_steps"
    repo TeacherAssistant.Repo

    references do
      reference :lesson_plan,
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
        :lesson_plan_id,
        :position,
        :etape,
        :duration_minutes,
        :contenus,
        :supports,
        :activites
      ],
      update: [:position, :etape, :duration_minutes, :contenus, :supports, :activites]
    ]

    # All steps of a lesson plan, in position order. Mirrors the old
    # `Academics.list_lesson_steps/1`.
    read :for_lesson_plan do
      argument :lesson_plan_id, :uuid, allow_nil?: false
      filter expr(lesson_plan_id == ^arg(:lesson_plan_id))
      prepare build(sort: [position: :asc])
    end

    # Owner-scoped single-step lookup (IDOR guard): the step must belong to
    # the given lesson plan. Backs `Curriculum.fetch_owned_lesson_step/2`.
    read :owned do
      argument :id, :uuid, allow_nil?: false
      argument :lesson_plan_id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and lesson_plan_id == ^arg(:lesson_plan_id))
    end

    # Swaps this step's position with its immediate neighbor (:up / :down);
    # a no-op at either end of the list. Mirrors the old
    # `Academics.move_lesson_step/2` exactly — same lookup, same swap, same
    # boundary no-op — as a single transactional update (the neighbor's
    # write happens in an `after_action` hook so both rows commit together).
    update :move do
      require_atomic? false
      argument :direction, :atom, constraints: [one_of: [:up, :down]], allow_nil?: false

      change fn changeset, context ->
        step = changeset.data
        direction = Ash.Changeset.get_argument(changeset, :direction)

        siblings =
          __MODULE__
          |> Ash.Query.filter(lesson_plan_id == ^step.lesson_plan_id)
          |> Ash.Query.sort(position: :asc)
          |> Ash.read!(scope: context)

        idx = Enum.find_index(siblings, &(&1.id == step.id))
        swap_idx = if direction == :up, do: idx && idx - 1, else: idx && idx + 1

        if is_nil(idx) or swap_idx < 0 or swap_idx >= length(siblings) do
          changeset
        else
          other = Enum.at(siblings, swap_idx)

          changeset
          |> Ash.Changeset.change_attribute(:position, other.position)
          |> Ash.Changeset.after_action(fn _changeset, updated_step ->
            case other
                 |> Ash.Changeset.for_update(:update, %{position: step.position}, scope: context)
                 |> Ash.update() do
              {:ok, _other} -> {:ok, updated_step}
              {:error, error} -> {:error, error}
            end
          end)
        end
      end
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

      authorize_if expr(
                     lesson_plan.progression_entry.progression_plan.teaching_context.teacher_user_id ==
                       ^actor(:id)
                   )

      authorize_if expr(
                     exists(
                       lesson_plan.progression_entry.progression_plan.combined_course.teaching_contexts,
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
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :etape, :string, allow_nil?: true, public?: true
    attribute :duration_minutes, :integer, allow_nil?: true, public?: true
    attribute :contenus, :string, allow_nil?: true, public?: true
    attribute :supports, :string, allow_nil?: true, public?: true
    attribute :activites, :string, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :lesson_plan, TeacherAssistant.Academics.LessonPlan do
      source_attribute :lesson_plan_id
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
