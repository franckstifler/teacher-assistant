defmodule TeacherAssistant.Academics.RollCallReminder do
  @moduledoc """
  Vie scolaire redesign §1.1: a « Relancer » sent to a slot's teacher whose roll
  call was not taken. At most one per slot and school day (`date`).
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Attendance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "roll_call_reminders"
    repo TeacherAssistant.Repo

    references do
      reference :timetable_slot,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :sent_by, on_delete: :nilify
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:timetable_slot_id, :date]
      change set_attribute(:sent_by_user_id, actor(:id))
    end

    read :on_date do
      argument :date, :date, allow_nil?: false
      filter expr(date == ^arg(:date))
    end
  end

  policies do
    policy action_type([:read, :create]) do
      authorize_if {Checks.SchoolRole, any_of: :conduct}
    end
  end

  validations do
    validate {TeacherAssistant.Academics.YearOpen, path: [:timetable_slot, :class_group]},
      on: [:create]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :date, :date, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :timetable_slot, TeacherAssistant.Academics.TimetableSlot do
      source_attribute :timetable_slot_id
      allow_nil? false
      public? true
    end

    belongs_to :sent_by, TeacherAssistant.Accounts.User do
      source_attribute :sent_by_user_id
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    # Slot ids are unique across schools, so the school need not be part of the key.
    identity :once_a_day, [:timetable_slot_id, :date], all_tenants?: true
  end
end
