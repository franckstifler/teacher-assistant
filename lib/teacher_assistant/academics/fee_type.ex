defmodule TeacherAssistant.Academics.FeeType do
  @moduledoc """
  A fee the school charges in an academic year (Fees 1): « Frais exigibles », « PTA »,
  « Frais informatique »… `position` is the payment order: a payment fills the lowest
  position first. The `:arrears` kind is last year's carried balance, always position 0.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Fees,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "fee_types"
    repo TeacherAssistant.Repo

    custom_indexes do
      # Composite-FK target: attribute multitenancy prefixes this to (workspace_id, id).
      index [:id], unique: true
    end

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
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:academic_year_id, :name, :position, :kind]
      change TeacherAssistant.Academics.Room.SetNameKey
    end

    update :update do
      primary? true
      accept [:name, :position, :active?]
      change TeacherAssistant.Academics.Room.SetNameKey
    end

    read :for_year do
      argument :academic_year_id, :uuid, allow_nil?: false
      filter expr(academic_year_id == ^arg(:academic_year_id))
      prepare build(sort: [position: :asc, name: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :fees}
    end
  end

  validations do
    validate {TeacherAssistant.Academics.YearOpen, path: []}, on: [:create, :update, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: true, allow_empty?: false, max_length: 80]

    attribute :name_key, :string, allow_nil?: false

    attribute :position, :integer,
      allow_nil?: false,
      default: 1,
      public?: true,
      constraints: [min: 0]

    attribute :kind, TeacherAssistant.Academics.FeeTypeKind,
      allow_nil?: false,
      default: :regular,
      public?: true

    attribute :active?, :boolean, allow_nil?: false, default: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_name, [:academic_year_id, :name_key]
  end
end
