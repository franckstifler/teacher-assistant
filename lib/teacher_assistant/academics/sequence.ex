defmodule TeacherAssistant.Academics.Sequence do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Organization,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "sequences"
    repo TeacherAssistant.Repo

    custom_indexes do
      # Composite-FK target: attribute multitenancy prefixes this to
      # (workspace_id, id), the unique key that tenant-matched references need.
      index [:id], unique: true
    end

    references do
      reference :term, match_with: [workspace_id: :workspace_id], match_type: :full, index?: true
      reference :workspace, on_delete: :delete, index?: true
    end

    check_constraints do
      check_constraint :end_date, "sequences_dates_ordered_check",
        check: "end_date >= start_date",
        message: "must not be before the start date"

      check_constraint :entry_deadline, "sequences_entry_deadline_after_end_check",
        check: "entry_deadline IS NULL OR entry_deadline >= end_date",
        message: "must not be before the end date"
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :number,
        :position_in_term,
        :start_date,
        :end_date,
        :integration_week,
        :term_id
      ],
      update: [
        :number,
        :position_in_term,
        :start_date,
        :end_date,
        :integration_week,
        :entry_deadline
      ]
    ]

    read :for_academic_year do
      argument :academic_year_id, :uuid, allow_nil?: false
      filter expr(term.academic_year_id == ^arg(:academic_year_id))
      prepare build(load: [:term, :grade_entry_deadline], sort: [number: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :number, :integer, allow_nil?: false, public?: true
    attribute :position_in_term, :integer, allow_nil?: false, public?: true
    attribute :start_date, :date, allow_nil?: false, public?: true
    attribute :end_date, :date, allow_nil?: false, public?: true
    attribute :entry_deadline, :date, public?: true
    attribute :integration_week, :boolean, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :term, TeacherAssistant.Academics.Term do
      source_attribute :term_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  calculations do
    calculate :grade_entry_deadline,
              :date,
              TeacherAssistant.Academics.Sequence.GradeEntryDeadline do
      public? true
    end
  end
end
