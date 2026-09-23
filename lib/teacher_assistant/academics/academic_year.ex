defmodule TeacherAssistant.Academics.AcademicYear do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Organization,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  postgres do
    table "academic_years"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:name, :start_date, :end_date, :active, :workspace_id],
      update: [:name, :start_date, :end_date, :active]
    ]

    # Mirrors the plain `:create` action, plus the "only one active year per
    # workspace" invariant: when the new year is created active, every other
    # active year of the same workspace is deactivated in the same after_action
    # (inside the create's own transaction).
    create :create_for_workspace do
      accept [:name, :start_date, :end_date, :active, :workspace_id]

      change after_action(fn _changeset, year, _context ->
               if year.active, do: deactivate_others(year.workspace_id, year.id)
               {:ok, year}
             end)
    end

    read :for_workspace do
      argument :workspace_id, :uuid, allow_nil?: false
      filter expr(workspace_id == ^arg(:workspace_id))
      prepare build(sort: [start_date: :desc])
    end

    read :active_for_workspace do
      argument :workspace_id, :uuid, allow_nil?: false
      filter expr(workspace_id == ^arg(:workspace_id) and active == true)
      prepare build(sort: [start_date: :desc])
    end

    # Activates this year and deactivates every other active year of the same
    # workspace (the before_action hook runs inside the update's own
    # transaction, same non-atomic-across-rows semantics as before).
    update :activate do
      accept []
      require_atomic? false

      change set_attribute(:active, true)

      change before_action(fn changeset, _context ->
               year = changeset.data
               deactivate_others(year.workspace_id, year.id)
               changeset
             end)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  validations do
    validate compare(:end_date, greater_than: :start_date),
      message: "must be after the start date"
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :start_date, :date, allow_nil?: false, public?: true
    attribute :end_date, :date, allow_nil?: false, public?: true
    attribute :active, :boolean, default: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    has_many :terms, TeacherAssistant.Academics.Term
  end

  identities do
    identity :unique_workspace_year, [:workspace_id, :name]
  end

  # Deactivates every other active year of `workspace_id`, keeping `keep_id`
  # untouched. Best-effort (not wrapped in its own transaction), same as the
  # original `Academics.deactivate_other_years/2`.
  defp deactivate_others(workspace_id, keep_id) do
    __MODULE__
    |> Ash.Query.filter(workspace_id == ^workspace_id and id != ^keep_id and active == true)
    |> Ash.read!()
    |> Enum.each(fn y ->
      y |> Ash.Changeset.for_update(:update, %{active: false}) |> Ash.update!()
    end)
  end
end
