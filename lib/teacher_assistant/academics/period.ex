defmodule TeacherAssistant.Academics.Period do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "periods"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:position, :label, :start_time, :end_time, :kind, :workspace_id],
      update: [:position, :label, :start_time, :end_time, :kind]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
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
