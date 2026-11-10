defmodule TeacherAssistant.Academics.FeeTranche do
  @moduledoc """
  A school-wide payment deadline of the year (Fees 1): by `due_date`, `percent` (cumulative)
  of each student's total due should be paid. Percent works for every class whatever its
  amounts.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Fees,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "fee_tranches"
    repo TeacherAssistant.Repo

    references do
      reference :academic_year,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:label, :percent, :due_date, :position, :academic_year_id],
      update: [:label, :percent, :due_date, :position]
    ]

    read :for_year do
      argument :academic_year_id, :uuid, allow_nil?: false
      filter expr(academic_year_id == ^arg(:academic_year_id))
      prepare build(sort: [due_date: :asc, position: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      # Row rules name a user, not a membership: require an active one.
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :fees}
    end
  end

  changes do
    change {TeacherAssistant.Academics.YearOpen, path: []},
      on: [:create, :update, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :label, :string, allow_nil?: false, public?: true

    attribute :percent, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: 100]

    attribute :due_date, :date, allow_nil?: false, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end
end
