defmodule TeacherAssistant.Academics.ClassCouncil do
  @moduledoc """
  A class's council for a trimester (spec I3) or the year (spec I4): its header (date, chair, attendees, general
  remarks), its status and a decision per student (`CouncilDecision`). Created by the
  first save; written only by the Proviseur and Censeur. `TeacherAssistant.Councils`
  refuses writes while the class's trimester is published.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "class_councils"
    repo TeacherAssistant.Repo

    custom_indexes do
      # (workspace_id, id), the unique key that tenant-matched references need.
      index [:id], unique: true
    end

    references do
      reference :class_group,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :academic_year,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :term, on_delete: :delete, index?: true
      reference :held_by, on_delete: :nilify
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    read :for_class_period do
      argument :class_group_id, :uuid, allow_nil?: false
      argument :period_key, :string, allow_nil?: false
      get? true
      filter expr(class_group_id == ^arg(:class_group_id) and period_key == ^arg(:period_key))
      prepare build(load: [:decisions])
    end

    read :for_period do
      argument :period_key, :string, allow_nil?: false
      filter expr(period_key == ^arg(:period_key))
    end

    create :open do
      accept [
        :class_group_id,
        :academic_year_id,
        :term_id,
        :period_key,
        :held_on,
        :starts_at,
        :chair,
        :attendees,
        :observations
      ]
    end

    update :edit do
      accept [:held_on, :starts_at, :chair, :attendees, :observations]
    end

    update :schedule do
      accept [:held_on, :starts_at]
    end

    update :hold do
      change set_attribute(:status, :held)
      change set_attribute(:held_at, &DateTime.utc_now/0)
      change set_attribute(:held_by_user_id, actor(:id))
    end

    update :reopen do
      change set_attribute(:status, :open)
      change set_attribute(:held_at, nil)
      change set_attribute(:held_by_user_id, nil)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  changes do
    change {TeacherAssistant.Academics.YearOpen, path: []}, on: [:create, :update, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :status, TeacherAssistant.Academics.CouncilStatus,
      allow_nil?: false,
      default: :open,
      public?: true

    # `Organization.period_param/1` of the period: "trim:<term id>" or "annee" (spec I4).
    attribute :period_key, :string, allow_nil?: false, public?: true
    attribute :held_on, :date, public?: true
    attribute :starts_at, :time, public?: true
    attribute :chair, :string, public?: true, constraints: [max_length: 200]
    attribute :attendees, :string, public?: true, constraints: [max_length: 2000]
    attribute :observations, :string, public?: true, constraints: [max_length: 4000]
    attribute :held_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    # nil for the annual council (spec I4).
    belongs_to :term, TeacherAssistant.Academics.Term do
      source_attribute :term_id
      public? true
    end

    belongs_to :held_by, TeacherAssistant.Accounts.User do
      source_attribute :held_by_user_id
      public? true
    end

    has_many :decisions, TeacherAssistant.Academics.CouncilDecision do
      destination_attribute :class_council_id
      public? true
    end
  end

  identities do
    identity :one_per_class_period, [:class_group_id, :period_key]
  end
end
