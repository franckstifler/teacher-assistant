defmodule TeacherAssistant.Academics.Subject do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "subjects"
    repo TeacherAssistant.Repo

    references do
      reference :workspace, on_delete: :delete, index?: true
    end

    custom_indexes do
      # Composite-FK target: attribute multitenancy prefixes this to
      # (workspace_id, id), the unique key that tenant-matched references need.
      index [:id], unique: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      update: [
        :name,
        :code,
        :default_coefficient,
        :bulletin_group,
        :position,
        :active?,
        :optional?
      ]
    ]

    create :create do
      primary? true

      accept [
        :name,
        :code,
        :default_coefficient,
        :bulletin_group,
        :position,
        :active?,
        :optional?
      ]

      change TeacherAssistant.Academics.Subject.SeedCoefficientCells
    end

    # Tenant scoping (attribute multitenancy) already restricts this to the
    # given workspace; no `workspace_id` argument is needed any more.
    read :for_workspace do
      prepare build(sort: [:position, :name])
    end

    update :deactivate do
      accept []
      change set_attribute(:active?, false)
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
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :code, :string, allow_nil?: true, public?: true

    attribute :default_coefficient, :decimal,
      allow_nil?: false,
      default: Decimal.new(1),
      public?: true

    attribute :bulletin_group, TeacherAssistant.Academics.BulletinGroup,
      allow_nil?: false,
      default: :g3_autres,
      public?: true

    attribute :position, :integer, allow_nil?: false, default: 0, public?: true
    attribute :active?, :boolean, allow_nil?: false, default: true, public?: true
    attribute :optional?, :boolean, allow_nil?: false, default: false, public?: true

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
    identity :unique_subject_name, [:workspace_id, :name]
  end
end
