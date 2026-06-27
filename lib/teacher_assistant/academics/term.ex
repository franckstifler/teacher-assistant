defmodule TeacherAssistant.Academics.Term do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "terms"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [:read, :destroy, create: [:position, :academic_year_id], update: [:position]]
  end

  policies do
    policy always() do
      authorize_if always()
    end
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

    has_many :sequences, TeacherAssistant.Academics.Sequence
  end

  identities do
    identity :unique_year_term, [:academic_year_id, :position]
  end
end
