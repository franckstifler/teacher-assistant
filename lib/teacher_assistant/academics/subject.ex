defmodule TeacherAssistant.Academics.Subject do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "subjects"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:name, :code, :default_coefficient, :category, :position, :active?, :workspace_id],
      update: [:name, :code, :default_coefficient, :category, :position, :active?]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :code, :string, allow_nil?: true, public?: true

    attribute :default_coefficient, :decimal,
      allow_nil?: false,
      default: Decimal.new(1),
      public?: true

    attribute :category, TeacherAssistant.Academics.SubjectCategory,
      allow_nil?: false,
      default: :general,
      public?: true

    attribute :position, :integer, allow_nil?: false, default: 0, public?: true
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
    identity :unique_subject_name, [:workspace_id, :name]
  end
end
