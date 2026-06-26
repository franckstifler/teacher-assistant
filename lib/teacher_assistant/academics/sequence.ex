defmodule TeacherAssistant.Academics.Sequence do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sequences"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:number, :position_in_term, :start_date, :end_date, :integration_week, :term_id],
      update: [:number, :position_in_term, :start_date, :end_date, :integration_week]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :number, :integer, allow_nil?: false, public?: true
    attribute :position_in_term, :integer, allow_nil?: false, public?: true
    attribute :start_date, :date, allow_nil?: false, public?: true
    attribute :end_date, :date, allow_nil?: false, public?: true
    attribute :integration_week, :boolean, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :term, TeacherAssistant.Academics.Term do
      source_attribute :term_id
      allow_nil? false
      public? true
    end
  end
end
