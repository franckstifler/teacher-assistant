defmodule TeacherAssistant.Academics.Term do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Organization,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "terms"
    repo TeacherAssistant.Repo

    references do
      reference :academic_year, index?: true
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:position, :academic_year_id],
      update: [:position]
    ]

    read :for_academic_year do
      argument :academic_year_id, :uuid, allow_nil?: false
      filter expr(academic_year_id == ^arg(:academic_year_id))
      prepare build(load: [:sequences], sort: [position: :asc])
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

    has_many :sequences, TeacherAssistant.Academics.Sequence
  end

  identities do
    identity :unique_year_term, [:academic_year_id, :position]
  end
end
