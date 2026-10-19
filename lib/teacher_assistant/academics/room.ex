defmodule TeacherAssistant.Academics.Room do
  @moduledoc """
  A room of the school (spec J3, T02): a class's home room or a shared room (lab,
  computer room, workshop, sports ground). Belongs to the school, not to a year.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Organization,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "rooms"
    repo TeacherAssistant.Repo

    custom_indexes do
      # Composite-FK target: attribute multitenancy prefixes this to (workspace_id, id).
      index [:id], unique: true
    end

    references do
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :kind, :capacity, :active?]
      change TeacherAssistant.Academics.Room.SetNameKey
    end

    update :update do
      primary? true
      accept [:name, :kind, :capacity, :active?]
      change TeacherAssistant.Academics.Room.SetNameKey
    end

    read :for_workspace do
      prepare build(sort: [:name_key])
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

    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: true, allow_empty?: false, max_length: 80]

    attribute :name_key, :string, allow_nil?: false

    attribute :kind, TeacherAssistant.Academics.RoomKind,
      allow_nil?: false,
      default: :classroom,
      public?: true

    attribute :capacity, :integer,
      allow_nil?: true,
      public?: true,
      constraints: [min: 1, max: 1000]

    attribute :active?, :boolean, allow_nil?: false, default: true, public?: true
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
    identity :unique_name, [:name_key]
  end
end
