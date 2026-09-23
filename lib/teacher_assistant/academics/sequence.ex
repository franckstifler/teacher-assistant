defmodule TeacherAssistant.Academics.Sequence do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Organization,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sequences"
    repo TeacherAssistant.Repo

    references do
      reference :term, index?: true
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :number,
        :position_in_term,
        :start_date,
        :end_date,
        :integration_week,
        :term_id,
        :workspace_id
      ],
      update: [:number, :position_in_term, :start_date, :end_date, :integration_week]
    ]

    read :for_academic_year do
      argument :academic_year_id, :uuid, allow_nil?: false
      filter expr(term.academic_year_id == ^arg(:academic_year_id))
      prepare build(load: [:term], sort: [number: :asc])
    end
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

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end
end
