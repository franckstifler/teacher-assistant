defmodule TeacherAssistant.Academics.Assessment do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # The owning domain (`TeacherAssistant.Assessment`) shares this module's last
  # name segment, so it is always referenced fully qualified below — a bare
  # `Assessment.<fn>` would rebind to this resource. `Curriculum` is the only
  # short alias.
  alias TeacherAssistant.Curriculum

  postgres do
    table "assessments"
    repo TeacherAssistant.Repo

    references do
      reference :teaching_context, index?: true
      reference :sequence, index?: true
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :label,
        :weight,
        :max_score,
        :given_on,
        :teaching_context_id,
        :sequence_id
      ],
      update: [:label, :weight, :max_score, :given_on]
    ]

    read :for_context_and_sequence do
      argument :teaching_context_id, :uuid, allow_nil?: false
      argument :sequence_id, :uuid, allow_nil?: false

      filter expr(
               teaching_context_id == ^arg(:teaching_context_id) and
                 sequence_id == ^arg(:sequence_id)
             )

      prepare build(sort: [inserted_at: :asc])
    end

    # Per-séquence assessments for a `CombinedCourse`: one underlying
    # `Assessment` row per member `TeachingContext` (a student's mark always
    # lands on their own class's context), grouped by label into one
    # teacher-facing column per séquence. If a member context is missing an
    # assessment for a label another member already has, the missing one is
    # created so every member class stays in sync for that séquence.
    #
    # Returns `[%{id, label, weight, max_score, by_class_group_id}]` — `id` is
    # a stable identifier for that logical column (the assessment id of the
    # course's first member class, by class label); `by_class_group_id` maps
    # each member `class_group_id` to that class's own `Assessment`, which is
    # what the marks upsert actually writes to.
    action :combined_for, {:array, :map} do
      argument :course, :struct,
        allow_nil?: false,
        constraints: [instance_of: TeacherAssistant.Academics.CombinedCourse]

      argument :sequence, :struct,
        allow_nil?: false,
        constraints: [instance_of: TeacherAssistant.Academics.Sequence]

      run fn input, _ctx ->
        {:ok, combined_for(input.arguments.course, input.arguments.sequence, input.tenant)}
      end
    end

    # Creates one `Assessment{label, sequence}` per member context of a
    # `CombinedCourse`, all inside one transaction (`transaction? true`) — the
    # create path behind `:combined_for`'s "same assessment across every member
    # class" guarantee. Returns `{:ok, [%Assessment{}, ...]}` (one per member
    # context) or rolls the whole batch back on the first failure.
    #
    # Skips a member context with no `class_group` yet, same as `:combined_for`
    # and `Curriculum.list_union_students/1` — a `class_group_id`-keyed map can
    # never reference such a context anyway.
    action :create_combined, {:array, :struct} do
      constraints items: [instance_of: __MODULE__]

      argument :course, :struct,
        allow_nil?: false,
        constraints: [instance_of: TeacherAssistant.Academics.CombinedCourse]

      argument :sequence, :struct,
        allow_nil?: false,
        constraints: [instance_of: TeacherAssistant.Academics.Sequence]

      argument :label, :string, allow_nil?: false

      transaction? true

      run fn input, _ctx ->
        %{course: course, sequence: seq, label: label} = input.arguments
        tenant = input.tenant

        contexts = course_member_contexts(course, tenant)

        Enum.reduce_while(contexts, {:ok, []}, fn ctx, {:ok, acc} ->
          case create_assessment(ctx, seq, label, tenant) do
            {:ok, assessment} -> {:cont, {:ok, acc ++ [assessment]}}
            {:error, reason} -> {:halt, {:error, reason}}
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

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :label, :string, allow_nil?: false, public?: true
    attribute :weight, :decimal, allow_nil?: false, default: Decimal.new(1), public?: true
    attribute :max_score, :decimal, allow_nil?: false, default: Decimal.new(20), public?: true
    attribute :given_on, :date, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? false
      public? true
    end

    belongs_to :sequence, TeacherAssistant.Academics.Sequence do
      source_attribute :sequence_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    has_many :marks, TeacherAssistant.Academics.Mark
  end

  # --- Combined-assessment helpers -------------------------------------------

  # Member contexts of a course that have a class group, in class-label order.
  defp course_member_contexts(course, tenant) do
    course.id
    |> Curriculum.contexts_of_course!(tenant: tenant)
    # `:class_group` is also multitenant — Ash needs a tenant to resolve the load.
    |> Ash.load!(:class_group, tenant: tenant)
    |> Enum.reject(&is_nil(&1.class_group))
    |> Enum.sort_by(&String.downcase(&1.class_group.label))
  end

  defp combined_for(course, seq, tenant) do
    case course_member_contexts(course, tenant) do
      [] ->
        []

      [primary | rest] = contexts ->
        by_context_id =
          Map.new(contexts, fn ctx -> {ctx.id, assessments_for(ctx.id, seq.id, tenant)} end)

        primary_labels = Enum.map(by_context_id[primary.id], & &1.label)

        extra_labels =
          rest
          |> Enum.flat_map(&by_context_id[&1.id])
          |> Enum.map(& &1.label)
          |> Enum.uniq()
          |> Enum.reject(&(&1 in primary_labels))

        (primary_labels ++ extra_labels)
        |> Enum.map(&build_combined_entry(&1, contexts, primary, by_context_id, seq, tenant))
    end
  end

  defp build_combined_entry(label, contexts, primary, by_context_id, seq, tenant) do
    by_class_group_id =
      Map.new(contexts, fn ctx ->
        assessment =
          Enum.find(by_context_id[ctx.id], &(&1.label == label)) ||
            backfill_assessment!(ctx, seq, label, tenant)

        {ctx.class_group_id, assessment}
      end)

    primary_assessment = Map.fetch!(by_class_group_id, primary.class_group_id)

    %{
      id: primary_assessment.id,
      label: label,
      weight: primary_assessment.weight,
      max_score: primary_assessment.max_score,
      by_class_group_id: by_class_group_id
    }
  end

  defp backfill_assessment!(ctx, seq, label, tenant) do
    case create_assessment(ctx, seq, label, tenant) do
      {:ok, assessment} ->
        assessment

      {:error, error} ->
        raise "could not sync combined assessment across member classes: #{inspect(error)}"
    end
  end

  defp assessments_for(teaching_context_id, sequence_id, tenant) do
    __MODULE__
    |> Ash.Query.for_read(:for_context_and_sequence, %{
      teaching_context_id: teaching_context_id,
      sequence_id: sequence_id
    })
    |> Ash.Query.set_tenant(tenant)
    |> Ash.read!()
  end

  defp create_assessment(ctx, seq, label, tenant) do
    __MODULE__
    |> Ash.Changeset.for_create(:create, %{
      label: label,
      teaching_context_id: ctx.id,
      sequence_id: seq.id
    })
    |> Ash.Changeset.set_tenant(tenant)
    |> Ash.create()
  end
end
