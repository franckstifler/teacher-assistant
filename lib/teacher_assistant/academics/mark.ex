defmodule TeacherAssistant.Academics.Mark do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "marks"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:score, :assessment_id, :student_id],
      update: [:score]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :score, :decimal, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :assessment, TeacherAssistant.Academics.Assessment do
      source_attribute :assessment_id
      allow_nil? false
      public? true
    end

    belongs_to :student, TeacherAssistant.Academics.Student do
      source_attribute :student_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_mark, [:assessment_id, :student_id]
  end
end
