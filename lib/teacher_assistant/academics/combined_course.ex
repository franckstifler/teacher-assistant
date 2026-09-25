defmodule TeacherAssistant.Academics.CombinedCourse do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  alias TeacherAssistant.Academics.{ProgressionPlan, TeachingContext}

  postgres do
    table "combined_courses"
    repo TeacherAssistant.Repo

    custom_indexes do
      # Composite-FK target: attribute multitenancy prefixes this to
      # (workspace_id, id), the unique key that tenant-matched references need.
      index [:id], unique: true
    end

    references do
      reference :workspace, on_delete: :delete, index?: true

      reference :academic_year,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :teacher, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:subject, :label, :academic_year_id, :teacher_user_id],
      update: [:label]
    ]

    # Combines several already-validated `TeachingContext`s into a fresh
    # `CombinedCourse`: creates the course, stamps `combined_course_id` on every
    # member, and creates the course's one shared `ProgressionPlan`. Runs in a
    # single transaction (`transaction? true`), so any failure rolls the whole
    # thing back. Count/teacher/subject/already-combined validation lives in
    # `Curriculum.combine_course/1`, which returns the bare error atoms callers
    # match on.
    action :combine, :struct do
      constraints instance_of: __MODULE__

      argument :contexts, {:array, :struct},
        allow_nil?: false,
        constraints: [items: [instance_of: TeachingContext]]

      transaction? true

      run fn input, _ctx ->
        # `build_label/1` needs `:class_group` on every member — the initiating
        # context in particular may arrive here without it preloaded (e.g. from
        # `Curriculum.list_assignments_for_class/1`, which only loads `:teacher`
        # and `:combined_course`). Load it here rather than trusting the caller.
        # `:class_group` is multitenant, and so is `TeachingContext` itself now
        # — `Curriculum.combine_course/1` validates every member shares one
        # workspace before this action runs and passes it as this action's
        # tenant, so `input.tenant` is the right tenant for every nested
        # query/changeset below.
        contexts = Ash.load!(input.arguments.contexts, :class_group, tenant: input.tenant)
        [first | _] = contexts

        with {:ok, course} <- create_course(first, build_label(contexts), input.tenant),
             :ok <- stamp_contexts(contexts, course.id, input.tenant),
             {:ok, _plan} <- create_course_plan(course, input.tenant) do
          {:ok, course}
        end
      end
    end

    # Splits a `CombinedCourse` apart: unlinks every member context
    # (`combined_course_id` back to `nil`), destroys the course's shared
    # `ProgressionPlan` (a split discards the shared fiche — the FK is
    # `on_delete: :nilify`, so the plan is not auto-removed and must be
    # destroyed explicitly), then destroys the course itself. Transactional.
    action :split do
      argument :course, :struct, allow_nil?: false, constraints: [instance_of: __MODULE__]

      transaction? true

      run fn input, _ctx ->
        course = input.arguments.course
        course_id = course.id
        tenant = input.tenant

        TeachingContext
        |> Ash.Query.filter(combined_course_id == ^course_id)
        |> Ash.Query.set_tenant(tenant)
        |> Ash.read!()
        |> Enum.each(fn ctx ->
          {:ok, _ctx, notifications} =
            ctx
            |> Ash.Changeset.for_update(:update, %{combined_course_id: nil})
            |> Ash.Changeset.set_tenant(tenant)
            |> Ash.update(return_notifications?: true)

          Ash.Notifier.notify(notifications)
        end)

        ProgressionPlan
        |> Ash.Query.filter(combined_course_id == ^course_id)
        |> Ash.Query.set_tenant(tenant)
        |> Ash.read!()
        |> Enum.each(&Ash.destroy!(&1, tenant: tenant))

        Ash.destroy!(course, tenant: tenant)

        :ok
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
    attribute :subject, :string, allow_nil?: false, public?: true
    attribute :label, :string, allow_nil?: false, public?: true
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

    belongs_to :teacher, TeacherAssistant.Accounts.User do
      source_attribute :teacher_user_id
      allow_nil? false
      public? true
    end
  end

  # --- Combine helpers -------------------------------------------------------

  defp create_course(%TeachingContext{} = first, label, tenant) do
    __MODULE__
    |> Ash.Changeset.for_create(:create, %{
      subject: first.subject,
      label: label,
      academic_year_id: first.academic_year_id,
      teacher_user_id: first.teacher_user_id
    })
    |> Ash.Changeset.set_tenant(tenant)
    |> Ash.create()
  end

  defp stamp_contexts(contexts, course_id, tenant) do
    Enum.reduce_while(contexts, :ok, fn ctx, :ok ->
      ctx
      |> Ash.Changeset.for_update(:update, %{combined_course_id: course_id})
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.update(return_notifications?: true)
      |> case do
        {:ok, _ctx, notifications} ->
          Ash.Notifier.notify(notifications)
          {:cont, :ok}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  # Mirrors `TeacherAssistant.Academics.create_course_plan/2` with empty attrs:
  # the course owns one plan titled after its subject.
  defp create_course_plan(%__MODULE__{} = course, tenant) do
    ProgressionPlan
    |> Ash.Changeset.for_create(:create, %{
      title: course.subject,
      combined_course_id: course.id,
      academic_year_id: course.academic_year_id
    })
    |> Ash.Changeset.set_tenant(tenant)
    |> Ash.create()
  end

  defp build_label(contexts) do
    subject = contexts |> List.first() |> Map.fetch!(:subject)

    labels =
      contexts
      |> Enum.map(&class_label/1)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()
      |> Enum.sort()

    subject <> " · " <> Enum.join(labels, "+")
  end

  defp class_label(%TeachingContext{class_group: %{label: label}}) when is_binary(label),
    do: label

  defp class_label(%TeachingContext{level: level, serie: nil}), do: level
  defp class_label(%TeachingContext{level: level, serie: serie}), do: level <> " " <> serie
end
