defmodule TeacherAssistant.Academics.AttendanceEntry do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Attendance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  # `TeacherAssistant.Attendance` is this resource's own owning domain, whose
  # module name shares this resource's data (both hold attendance logic) —
  # never aliased, always referenced fully qualified below, so a bare
  # `Attendance.<fn>` can never accidentally resolve here.
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.CombinedCourse
  alias TeacherAssistant.Academics.Period
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.TimetableSlot

  postgres do
    table "attendance_entries"
    repo TeacherAssistant.Repo

    references do
      reference :enrollment, on_delete: :delete
      reference :period, on_delete: :delete
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :date,
        :status,
        :justified,
        :justification_note,
        :recorded_by_user_id,
        :workspace_id,
        :enrollment_id,
        :period_id,
        :teaching_context_id
      ],
      update: [
        :date,
        :status,
        :justified,
        :justification_note,
        :recorded_by_user_id
      ]
    ]

    create :record do
      accept [
        :status,
        :justified,
        :justification_note,
        :teaching_context_id,
        :recorded_by_user_id,
        :workspace_id,
        :enrollment_id,
        :date,
        :period_id
      ]

      upsert? true
      upsert_identity :unique_mark
    end

    read :for_period_date_class do
      argument :period_id, :uuid, allow_nil?: false
      argument :date, :date, allow_nil?: false
      argument :class_group_id, :uuid, allow_nil?: false

      filter expr(
               period_id == ^arg(:period_id) and date == ^arg(:date) and
                 enrollment.class_group_id == ^arg(:class_group_id)
             )
    end

    read :for_date_periods_class do
      argument :date, :date, allow_nil?: false
      argument :period_ids, {:array, :uuid}, allow_nil?: false
      argument :class_group_id, :uuid, allow_nil?: false

      filter expr(
               date == ^arg(:date) and period_id in ^arg(:period_ids) and
                 enrollment.class_group_id == ^arg(:class_group_id)
             )
    end

    read :absences_for_day do
      argument :enrollment_id, :uuid, allow_nil?: false
      argument :date, :date, allow_nil?: false

      filter expr(
               enrollment_id == ^arg(:enrollment_id) and date == ^arg(:date) and status == :absent
             )
    end

    read :for_enrollment_range do
      argument :enrollment_id, :uuid, allow_nil?: false
      argument :first, :date, allow_nil?: false
      argument :last, :date, allow_nil?: false

      filter expr(
               enrollment_id == ^arg(:enrollment_id) and date >= ^arg(:first) and
                 date <= ^arg(:last)
             )

      prepare build(load: [:period])
    end

    read :for_class_range do
      argument :class_group_id, :uuid, allow_nil?: false
      argument :first, :date, allow_nil?: false
      argument :last, :date, allow_nil?: false

      filter expr(
               enrollment.class_group_id == ^arg(:class_group_id) and date >= ^arg(:first) and
                 date <= ^arg(:last)
             )

      prepare build(load: [:period])
    end

    # Builds the roll for `class_group`/`period`/`date`: every roster student
    # with their current attendance status (`nil` when unmarked), plus the
    # teaching context for that slot (if any). Read-only composition — safe
    # to run as a plain generic action (no custom error atoms to preserve).
    action :period_roll, :map do
      argument :class_group, :struct, allow_nil?: false, constraints: [instance_of: ClassGroup]
      argument :period, :struct, allow_nil?: false, constraints: [instance_of: Period]
      argument :date, :date, allow_nil?: false

      run fn input, _ctx ->
        %{class_group: cg, period: period, date: date} = input.arguments
        {:ok, period_roll(cg, period, date)}
      end
    end

    # Builds the union roll for a `CombinedCourse`/`period`/`date`: `period_roll`
    # run once per member class, concatenated as one group per class — each
    # group has the same shape `period_roll` returns (`:students`,
    # `:teaching_context`) plus its own `:class_group`. A combined attendance
    # session shows every member class's roster in one screen; recording still
    # writes each entry to the student's own class (see
    # `:record_combined_period`) — this is purely a read shape, it never
    # merges rosters across classes into one flat list.
    #
    # Skips a member context with no `class_group` yet, same as
    # `Curriculum.list_union_students/1`.
    action :combined_period_roll, {:array, :map} do
      argument :course, :struct, allow_nil?: false, constraints: [instance_of: CombinedCourse]
      argument :period, :struct, allow_nil?: false, constraints: [instance_of: Period]
      argument :date, :date, allow_nil?: false

      run fn input, _ctx ->
        %{course: course, period: period, date: date} = input.arguments
        {:ok, combined_roll(course, period, date)}
      end
    end

    # Writes one combined attendance session: `groups` (pre-validated and
    # pre-routed by `TeacherAssistant.Attendance.record_combined_period/5` —
    # each entry already carries its own class's `workspace_id`/
    # `teaching_context_id`, the server-derived per-class routing) are written
    # via the same `:record` upsert (identity `[:enrollment_id, :date,
    # :period_id]`) used by a solo roll. `transaction? true` wraps every
    # group's writes in one DB transaction, so a write failure in ANY class
    # rolls back every class's marks — no partial commit across a combined
    # course's member classes (mirrors `Mark.:upsert_all`, C7's record-once-
    # combined pattern). Status/enrollment validation happens in the domain
    # wrapper *before* this action is ever called, so a bad mark never opens a
    # transaction at all — this action only ever sees already-valid writes.
    action :record_combined_period, :integer do
      argument :period_id, :uuid, allow_nil?: false
      argument :date, :date, allow_nil?: false
      argument :recorded_by_user_id, :uuid, allow_nil?: true
      argument :groups, {:array, :map}, allow_nil?: false

      transaction? true

      run fn input, _ctx ->
        %{period_id: period_id, date: date, recorded_by_user_id: uid, groups: groups} =
          input.arguments

        groups
        |> Enum.reduce_while({:ok, 0}, fn group, {:ok, acc} ->
          case create_group_entries(group, period_id, date, uid) do
            {:ok, count} -> {:cont, {:ok, acc + count}}
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

  attributes do
    uuid_v7_primary_key :id

    attribute :date, :date, allow_nil?: false, public?: true

    attribute :status, TeacherAssistant.Academics.AttendanceStatus,
      allow_nil?: false,
      public?: true

    attribute :justified, :boolean, allow_nil?: false, default: false, public?: true
    attribute :justification_note, :string, allow_nil?: true, public?: true
    attribute :recorded_by_user_id, :uuid, allow_nil?: true, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :enrollment, TeacherAssistant.Academics.Enrollment do
      source_attribute :enrollment_id
      allow_nil? false
      public? true
    end

    belongs_to :period, TeacherAssistant.Academics.Period do
      source_attribute :period_id
      allow_nil? false
      public? true
    end

    belongs_to :teaching_context, TeacherAssistant.Academics.TeachingContext do
      source_attribute :teaching_context_id
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :unique_mark, [:enrollment_id, :date, :period_id]
  end

  # --- Roll composition (private engine behind :period_roll /
  # :combined_period_roll) ----------------------------------------------------

  defp period_roll(%ClassGroup{} = class_group, %Period{id: period_id}, %Date{} = date) do
    teaching_context =
      case slot_for(class_group, date, period_id) do
        {:ok, %TimetableSlot{teaching_context: %TeachingContext{} = tc}} -> tc
        _ -> nil
      end

    statuses =
      __MODULE__
      |> Ash.Query.for_read(:for_period_date_class, %{
        period_id: period_id,
        date: date,
        class_group_id: class_group.id
      })
      |> Ash.read!()
      |> Map.new(&{&1.enrollment_id, &1.status})

    students =
      class_group
      |> Enrollment.list_roster()
      |> Enum.map(fn %{student: student, enrollment: enrollment} ->
        %{
          enrollment_id: enrollment.id,
          student_name: student.full_name,
          status: Map.get(statuses, enrollment.id)
        }
      end)

    %{students: students, teaching_context: teaching_context}
  end

  defp combined_roll(%CombinedCourse{} = course, %Period{} = period, %Date{} = date) do
    course.id
    |> Curriculum.contexts_of_course!()
    |> Ash.load!(:class_group)
    |> Enum.reject(&is_nil(&1.class_group))
    |> Enum.map(fn ctx ->
      ctx.class_group
      |> period_roll(period, date)
      |> Map.put(:class_group, ctx.class_group)
    end)
    |> Enum.sort_by(&String.downcase(&1.class_group.label))
  end

  # Resolves the placed `TimetableSlot` (with `teaching_context` loaded) for
  # `class_group` at `date`'s day-of-week/`period_id`. Purely internal to
  # `period_roll/3` above — `TeacherAssistant.Attendance.slot_for/3` is the
  # public entry point for direct callers and duplicates this small query
  # deliberately: its `{:error, :no_slot}` return must survive untouched,
  # which a Ash generic action cannot guarantee (a bare atom error returned
  # from an action's `run` gets normalized into an `Ash.Error.Unknown`), so it
  # is never routed through an action boundary.
  defp slot_for(%ClassGroup{id: cg_id}, %Date{} = date, period_id) do
    with {:ok, day} <- day_of_week(date) do
      TimetableSlot
      |> Ash.Query.filter(class_group_id == ^cg_id and day == ^day and period_id == ^period_id)
      |> Ash.Query.load(:teaching_context)
      |> Ash.read_one!()
      |> case do
        nil -> {:error, :no_slot}
        %TimetableSlot{} = slot -> {:ok, slot}
      end
    end
  end

  defp day_of_week(%Date{} = date) do
    case Date.day_of_week(date) do
      1 -> {:ok, :monday}
      2 -> {:ok, :tuesday}
      3 -> {:ok, :wednesday}
      4 -> {:ok, :thursday}
      5 -> {:ok, :friday}
      6 -> {:ok, :saturday}
      _ -> {:error, :no_slot}
    end
  end

  # --- Combined-write engine (private, behind :record_combined_period) -------

  # Creates one `AttendanceEntry` per mark in `group` (upsert via `:record`,
  # identity `[:enrollment_id, :date, :period_id]`). `group` carries its own
  # `workspace_id`/`teaching_context_id` — the per-class routing computed by
  # `TeacherAssistant.Attendance.record_combined_period/5` before this action
  # ever runs. Returns `{:ok, count}`, or the first `{:error, reason}` hit
  # (halting the batch — the caller's `transaction? true` rolls back whatever
  # earlier groups already wrote).
  defp create_group_entries(
         %{workspace_id: ws_id, teaching_context_id: tc_id, marks: marks},
         period_id,
         date,
         recorded_by_user_id
       ) do
    results =
      Enum.map(marks, fn %{enrollment_id: enrollment_id, status: status} ->
        __MODULE__
        |> Ash.Changeset.for_create(:record, %{
          date: date,
          status: status,
          enrollment_id: enrollment_id,
          period_id: period_id,
          teaching_context_id: tc_id,
          recorded_by_user_id: recorded_by_user_id,
          workspace_id: ws_id
        })
        |> Ash.create()
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, length(results)}
      {:error, error} -> {:error, error}
    end
  end
end
