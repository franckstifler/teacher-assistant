defmodule TeacherAssistant.Academics.LessonNotHeld do
  @moduledoc """
  Paper roll call (spec 2026-10-28 §3): « cours non assuré » — a class's lesson that did
  not take place on a date. It closes the lesson without any attendance entry, so it is
  neither on paper nor missed. At most one per class, date and period.

  Roll call outside the timetable (spec 2026-11-12): the slot's own teacher marks it
  « déplacé à <period> » (`:mark_moved`, `moved_to_period`) when they held that lesson
  at another hour of the day; the surveillant's marking (`:mark`) carries no motive.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Attendance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "lessons_not_held"
    repo TeacherAssistant.Repo

    references do
      reference :class_group,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :period,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full

      # Nullable: MATCH SIMPLE, or a NULL motive next to a workspace id is refused.
      reference :moved_to_period,
        on_delete: :nilify,
        match_with: [workspace_id: :workspace_id],
        match_type: :simple

      reference :marked_by, on_delete: :nilify
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :mark do
      accept [:class_group_id, :period_id, :date]
      change set_attribute(:marked_by_user_id, actor(:id))
    end

    # The slot's teacher (or a conduct manager) says the lesson was held at
    # `moved_to_period` instead; re-marking updates the motive.
    create :mark_moved do
      accept [:class_group_id, :period_id, :date, :moved_to_period_id]
      upsert? true
      upsert_identity :one_per_lesson
      upsert_fields [:moved_to_period_id, :marked_by_user_id]
      change set_attribute(:marked_by_user_id, actor(:id))
      validate present(:moved_to_period_id)

      validate fn changeset, _context ->
        if Ash.Changeset.get_attribute(changeset, :moved_to_period_id) ==
             Ash.Changeset.get_attribute(changeset, :period_id),
           do:
             {:error,
              field: :moved_to_period_id,
              message: "Le cours ne peut pas être déplacé sur son propre créneau."},
           else: :ok
      end
    end

    read :for_classes_range do
      argument :class_group_ids, {:array, :uuid}, allow_nil?: false
      argument :first, :date, allow_nil?: false
      argument :last, :date, allow_nil?: false

      filter expr(
               class_group_id in ^arg(:class_group_ids) and date >= ^arg(:first) and
                 date <= ^arg(:last)
             )
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action(:mark_moved) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
      authorize_if TeacherAssistant.Academics.LessonNotHeld.OwnsSlot
    end

    policy action(:mark) do
      authorize_if {Checks.SchoolRole, any_of: :conduct}
    end

    # The same-day rule for the marker lives in `Attendance.unmark_moved/4`.
    policy action_type(:destroy) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
      authorize_if expr(marked_by_user_id == ^actor(:id))
    end
  end

  changes do
    change {TeacherAssistant.Academics.YearOpen, path: [:class_group]},
      on: [:create, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :date, :date, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end

    belongs_to :period, TeacherAssistant.Academics.Period do
      source_attribute :period_id
      allow_nil? false
      public? true
    end

    belongs_to :moved_to_period, TeacherAssistant.Academics.Period do
      source_attribute :moved_to_period_id
      allow_nil? true
      public? true
    end

    belongs_to :marked_by, TeacherAssistant.Accounts.User do
      source_attribute :marked_by_user_id
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    # Class ids are unique across schools, so the school need not be part of the key.
    identity :one_per_lesson, [:class_group_id, :date, :period_id], all_tenants?: true
  end
end
