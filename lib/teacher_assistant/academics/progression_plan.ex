defmodule TeacherAssistant.Academics.ProgressionPlan do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  alias TeacherAssistant.Academics.{ProgressionEntry, ProgressionModule, TeachingContext}

  postgres do
    table "progression_plans"
    repo TeacherAssistant.Repo

    references do
      reference :combined_course, on_delete: :nilify, index?: true
      reference :teaching_context, index?: true
      reference :academic_year, index?: true
      reference :workspace, on_delete: :delete, index?: true
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

    # Creates a draft plan and its entries from imported rows in a single
    # transaction (`transaction? true`) — any failure returns `{:error, _}` and
    # rolls the whole thing back, so no orphan plan survives. Notifications from
    # the nested creates are buffered by Ash inside the transaction and only
    # dispatched on commit, so a rolled-back import emits no phantom PubSub
    # events. Owner-scoping (the context must belong to the workspace) is done
    # in `Curriculum.import_progression_plan/3`, which returns the bare
    # `{:error, :not_found}` atom before invoking this action.
    action :import, :struct do
      constraints instance_of: __MODULE__

      argument :teaching_context, :struct,
        allow_nil?: false,
        constraints: [instance_of: TeachingContext]

      argument :title, :string, allow_nil?: false
      argument :rows, {:array, :map}, allow_nil?: false

      transaction? true

      run fn input, _ctx ->
        ctx = input.arguments.teaching_context
        rows = input.arguments.rows

        with {:ok, plan} <-
               __MODULE__
               |> Ash.Changeset.for_create(:create, %{
                 title: input.arguments.title,
                 status: :draft,
                 teaching_context_id: ctx.id,
                 academic_year_id: ctx.academic_year_id,
                 workspace_id: ctx.workspace_id
               })
               |> Ash.create() do
          groups = TeacherAssistant.Academics.ModuleGrouping.group(index_rows(rows))
          rows_by_index = rows |> Enum.with_index() |> Map.new(fn {r, i} -> {i, r} end)

          groups
          |> Enum.with_index(1)
          |> Enum.reduce_while(:ok, fn {%{key: key, entry_ids: row_indexes}, mod_pos}, :ok ->
            case create_import_module(plan, key, mod_pos) do
              {:ok, module} ->
                row_indexes
                |> Enum.with_index(1)
                |> Enum.reduce_while(:ok, fn {row_index, entry_pos}, :ok ->
                  entry_attrs =
                    rows_by_index
                    |> Map.fetch!(row_index)
                    |> Map.take([
                      :lesson_title,
                      :planned_hours,
                      :entry_type,
                      :week_no,
                      :sequence_id
                    ])
                    |> Map.put(:progression_plan_id, plan.id)
                    |> Map.put(:progression_module_id, module.id)
                    |> Map.put(:position, entry_pos)
                    |> Map.put(:workspace_id, plan.workspace_id)

                  case ProgressionEntry
                       |> Ash.Changeset.for_create(:create, entry_attrs)
                       |> Ash.create() do
                    {:ok, _entry} -> {:cont, :ok}
                    {:error, reason} -> {:halt, {:error, reason}}
                  end
                end)
                |> case do
                  :ok -> {:cont, :ok}
                  {:error, reason} -> {:halt, {:error, reason}}
                end

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          end)
          |> case do
            :ok -> {:ok, plan}
            {:error, reason} -> {:error, reason}
          end
        end
      end
    end

    # Applies a validated drag-and-drop layout — a list of
    # `%{"module_id" => id, "entry_ids" => [id, ...]}` in target order —
    # renumbering module positions and moving/renumbering entries, all in one
    # transaction (`transaction? true`). Layout validation (the id-sets must
    # match the plan's modules/entries exactly) lives in
    # `Curriculum.apply_layout/2`, which returns `{:error, :invalid_layout}`
    # before invoking this action.
    action :apply_layout, :atom do
      argument :plan, :struct, allow_nil?: false, constraints: [instance_of: __MODULE__]
      argument :layout, {:array, :map}, allow_nil?: false

      transaction? true

      run fn input, _ctx ->
        plan_id = input.arguments.plan.id
        layout = input.arguments.layout

        module_by_id =
          ProgressionModule
          |> Ash.Query.filter(progression_plan_id == ^plan_id)
          |> Ash.read!()
          |> Map.new(&{&1.id, &1})

        entry_by_id =
          ProgressionEntry
          |> Ash.Query.filter(progression_plan_id == ^plan_id)
          |> Ash.read!()
          |> Map.new(&{&1.id, &1})

        layout
        |> Enum.with_index(1)
        |> Enum.reduce_while(:ok, fn {%{"module_id" => mid, "entry_ids" => eids}, mpos}, :ok ->
          case module_by_id[mid]
               |> Ash.Changeset.for_update(:update, %{position: mpos})
               |> Ash.update() do
            {:ok, _module} ->
              eids
              |> Enum.with_index(1)
              |> Enum.reduce_while(:ok, fn {eid, epos}, :ok ->
                case entry_by_id[eid]
                     |> Ash.Changeset.for_update(:update, %{
                       progression_module_id: mid,
                       position: epos
                     })
                     |> Ash.update() do
                  {:ok, _entry} -> {:cont, :ok}
                  {:error, reason} -> {:halt, {:error, reason}}
                end
              end)
              |> case do
                :ok -> {:cont, :ok}
                {:error, reason} -> {:halt, {:error, reason}}
              end

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)
        |> case do
          :ok -> {:ok, :applied}
          {:error, reason} -> {:error, reason}
        end
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

  # --- Import helpers --------------------------------------------------------

  # `ModuleGrouping.group/1` keys entries by `:id`; feed it each row's *index*
  # as the id so the resulting groups can be mapped back to rows.
  defp index_rows(rows) do
    rows
    |> Enum.with_index()
    |> Enum.map(fn {r, i} -> %{id: i, module: Map.get(r, :module), position: i} end)
  end

  defp create_import_module(plan, :default, pos) do
    ProgressionModule
    |> Ash.Changeset.for_create(:create_default_bucket, %{
      title: "Général",
      position: pos,
      progression_plan_id: plan.id,
      workspace_id: plan.workspace_id
    })
    |> Ash.create()
  end

  defp create_import_module(plan, title, pos) when is_binary(title) do
    ProgressionModule
    |> Ash.Changeset.for_create(:create, %{
      title: title,
      position: pos,
      progression_plan_id: plan.id,
      workspace_id: plan.workspace_id
    })
    |> Ash.create()
  end
end
