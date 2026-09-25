defmodule TeacherAssistant.Academics.TeachingLogEntry do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "teaching_log_entries"
    repo TeacherAssistant.Repo

    references do
      reference :workspace, on_delete: :delete, index?: true

      reference :progression_entry,
        match_with: [workspace_id: :workspace_id],
        match_type: :simple,
        index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :date,
        :content_taught,
        :hours,
        :status,
        :homework,
        :note,
        :progression_entry_id
      ],
      update: [:date, :content_taught, :hours, :status, :homework, :note, :progression_entry_id]
    ]

    # All log entries whose progression entry belongs to a plan, most recent
    # first. Mirrors the old `Academics.list_logs_for_plan/1` (previously two
    # queries — id-list then `in`; expressed here as one relationship-path
    # filter with the same exclusion of entry-less logs).
    read :for_plan do
      argument :progression_plan_id, :uuid, allow_nil?: false
      filter expr(progression_entry.progression_plan_id == ^arg(:progression_plan_id))
      prepare build(sort: [date: :desc])
    end

    # The `limit` most recent log entries of a workspace. Tenant scoping
    # (attribute multitenancy) already restricts this to the given workspace;
    # no `workspace_id` argument is needed any more. Mirrors the old
    # `Academics.list_recent_logs/2`.
    read :recent do
      argument :limit, :integer, allow_nil?: false, default: 10
      prepare build(sort: [date: :desc])

      prepare fn query, _context ->
        Ash.Query.limit(query, Ash.Query.get_argument(query, :limit))
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
    attribute :date, :date, allow_nil?: false, public?: true
    attribute :content_taught, :string, allow_nil?: false, public?: true
    attribute :hours, :decimal, default: Decimal.new("1"), public?: true

    attribute :status, TeacherAssistant.Academics.TeachingLogStatus,
      default: :done,
      allow_nil?: false,
      public?: true

    attribute :homework, :string, allow_nil?: true, public?: true
    attribute :note, :string, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :progression_entry, TeacherAssistant.Academics.ProgressionEntry do
      source_attribute :progression_entry_id
      allow_nil? true
      public? true
    end
  end
end
