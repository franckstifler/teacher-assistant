defmodule TeacherAssistant.Academics.Period do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Attendance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "periods"
    repo TeacherAssistant.Repo

    custom_indexes do
      # Composite-FK target: attribute multitenancy prefixes this to
      # (workspace_id, id), the unique key that tenant-matched references need.
      index [:id], unique: true
    end

    references do
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:position, :label, :start_time, :end_time, :kind],
      update: [:position, :label, :start_time, :end_time, :kind]
    ]

    # Tenant scoping (attribute multitenancy) already restricts this to the
    # given workspace; no `workspace_id` argument is needed any more.
    read :for_workspace do
      prepare build(sort: [position: :asc])
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

    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :label, :string, allow_nil?: false, public?: true
    attribute :start_time, :time, allow_nil?: false, public?: true
    attribute :end_time, :time, allow_nil?: false, public?: true

    attribute :kind, TeacherAssistant.Academics.PeriodKind,
      allow_nil?: false,
      default: :lesson,
      public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_period_position, [:workspace_id, :position]
  end
end
