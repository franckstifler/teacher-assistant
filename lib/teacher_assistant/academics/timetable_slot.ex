defmodule TeacherAssistant.Academics.TimetableSlot do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Timetabling,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "timetable_slots"
    repo TeacherAssistant.Repo

    custom_indexes do
      index [:workspace_id, :teaching_context_id]
    end

    references do
      reference :class_group, on_delete: :delete, index?: true
      reference :teaching_context, on_delete: :delete, index?: true
      reference :period, index?: true
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:class_group_id, :teaching_context_id, :period_id, :day, :workspace_id],
      update: [:class_group_id, :teaching_context_id, :period_id, :day, :workspace_id]
    ]

    # Places (or replaces) the occupant of one (class_group, day, period)
    # cell. `unique_cell` makes this an upsert: an existing row at the same
    # cell keeps its id and only `teaching_context_id` changes — mirrors the
    # old `upsert_slot/4`'s read-then-branch, without the extra read.
    create :place do
      accept [:class_group_id, :teaching_context_id, :period_id, :day, :workspace_id]

      upsert? true
      upsert_identity :unique_cell
      upsert_fields [:teaching_context_id]
    end

    read :for_class do
      argument :class_group_id, :uuid, allow_nil?: false

      filter expr(class_group_id == ^arg(:class_group_id))

      prepare build(load: [teaching_context: :teacher])
    end

    read :for_workspace_teacher do
      argument :workspace_id, :uuid, allow_nil?: false
      argument :teacher_user_id, :uuid, allow_nil?: false

      filter expr(
               workspace_id == ^arg(:workspace_id) and
                 teaching_context.teacher_user_id == ^arg(:teacher_user_id)
             )

      prepare build(load: [:class_group, teaching_context: :teacher])
    end

    read :for_cell do
      argument :class_group_id, :uuid, allow_nil?: false
      argument :day, TeacherAssistant.Academics.DayOfWeek, allow_nil?: false
      argument :period_id, :uuid, allow_nil?: false

      filter expr(
               class_group_id == ^arg(:class_group_id) and day == ^arg(:day) and
                 period_id == ^arg(:period_id)
             )
    end

    read :for_period do
      argument :period_id, :uuid, allow_nil?: false

      filter expr(period_id == ^arg(:period_id))
    end

    read :for_clash_check do
      argument :workspace_id, :uuid, allow_nil?: false
      argument :day, TeacherAssistant.Academics.DayOfWeek, allow_nil?: false
      argument :period_id, :uuid, allow_nil?: false
      argument :teacher_user_id, :uuid, allow_nil?: false
      argument :exclude_class_group_ids, {:array, :uuid}, allow_nil?: false, default: []

      filter expr(
               workspace_id == ^arg(:workspace_id) and day == ^arg(:day) and
                 period_id == ^arg(:period_id) and
                 class_group_id not in ^arg(:exclude_class_group_ids) and
                 teaching_context.teacher_user_id == ^arg(:teacher_user_id)
             )
    end

    # Places a `TimetableSlot` for every member class of a combined course at
    # the same `day`/`period_id`, one call per member (`placements`, each
    # `%{class_group_id, teaching_context_id, workspace_id}`). `transaction?
    # true` wraps every member's upsert in one DB transaction, so a failure
    # for any member rolls back every member already placed in this call —
    # no partial commit across a combined course's classes. The teacher-clash
    # guard (with the member classes exempted from clashing against each
    # other) runs in `TeacherAssistant.Timetabling.place_combined_slot/3`
    # *before* this action is ever called — this action only ever performs
    # already-validated writes, mirroring `AttendanceEntry.:record_combined_period`.
    action :place_combined, {:array, :struct} do
      constraints items: [instance_of: __MODULE__]

      argument :day, TeacherAssistant.Academics.DayOfWeek, allow_nil?: false
      argument :period_id, :uuid, allow_nil?: false
      argument :placements, {:array, :map}, allow_nil?: false

      transaction? true

      run fn input, _ctx ->
        %{day: day, period_id: period_id, placements: placements} = input.arguments

        placements
        |> Enum.reduce_while({:ok, []}, fn placement, {:ok, acc} ->
          case place_one(placement, day, period_id) do
            {:ok, slot} -> {:cont, {:ok, [slot | acc]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, slots} -> {:ok, Enum.reverse(slots)}
          {:error, reason} -> {:error, reason}
        end
      end
    end

    # Clears the (day, period) cell for every member class of a combined
    # course (`class_group_ids`). Mirrors `:place_combined`'s per-member loop
    # but for destroys; `transaction? true` for the same all-or-nothing
    # reasoning. Always succeeds (clearing an empty cell is a no-op), so this
    # never needs to surface a custom error atom.
    action :clear_combined, :atom do
      argument :day, TeacherAssistant.Academics.DayOfWeek, allow_nil?: false
      argument :period_id, :uuid, allow_nil?: false
      argument :class_group_ids, {:array, :uuid}, allow_nil?: false

      transaction? true

      run fn input, _ctx ->
        %{day: day, period_id: period_id, class_group_ids: class_group_ids} = input.arguments

        Enum.each(class_group_ids, fn class_group_id ->
          __MODULE__
          |> Ash.Query.for_read(:for_cell, %{
            class_group_id: class_group_id,
            day: day,
            period_id: period_id
          })
          |> Ash.read!()
          |> Enum.each(&Ash.destroy!/1)
        end)

        {:ok, :ok}
      end
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :day, TeacherAssistant.Academics.DayOfWeek,
      allow_nil?: false,
      public?: true

    timestamps()
  end

  relationships do
    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end

    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? false
      public? true
    end

    belongs_to :period, TeacherAssistant.Academics.Period do
      source_attribute :period_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_cell, [:class_group_id, :day, :period_id]
  end

  defp place_one(
         %{class_group_id: cg_id, teaching_context_id: tc_id, workspace_id: ws_id},
         day,
         period_id
       ) do
    __MODULE__
    |> Ash.Changeset.for_create(:place, %{
      class_group_id: cg_id,
      teaching_context_id: tc_id,
      period_id: period_id,
      day: day,
      workspace_id: ws_id
    })
    |> Ash.create()
  end
end
