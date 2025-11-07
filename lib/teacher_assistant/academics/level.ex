defmodule TeacherAssistant.Academics.Level do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo TeacherAssistant.Repo
    table "levels"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :description]
      argument :option_ids, {:array, :uuid_v7}, default: []

      change manage_relationship(:option_ids, :options, type: :append_and_remove)
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:name, :description]
      argument :option_ids, {:array, :uuid_v7}, default: []

      change manage_relationship(:option_ids, :options, type: :append_and_remove)
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :description, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School

    many_to_many :options, TeacherAssistant.Academics.Option do
      through TeacherAssistant.Academics.LevelOption
      source_attribute_on_join_resource :level_id
      destination_attribute_on_join_resource :option_id
    end
  end

  identities do
    identity :unique_name, [:school_id, :name]
  end
end
