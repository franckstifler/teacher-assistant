defmodule TeacherAssistant.Academics.SanctionEntry do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sanction_entries"
    repo TeacherAssistant.Repo

    references do
      reference :enrollment, on_delete: :delete
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :type,
        :date,
        :reason,
        :duration_days,
        :issued_by_user_id,
        :workspace_id,
        :enrollment_id
      ],
      update: [
        :type,
        :date,
        :reason,
        :duration_days,
        :issued_by_user_id
      ]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :type, TeacherAssistant.Academics.SanctionType, allow_nil?: false, public?: true

    attribute :date, :date, allow_nil?: false, public?: true
    attribute :reason, :string, allow_nil?: true, public?: true
    attribute :duration_days, :integer, allow_nil?: true, public?: true
    attribute :issued_by_user_id, :uuid, allow_nil?: true, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :enrollment, TeacherAssistant.Academics.Enrollment do
      source_attribute :enrollment_id
      allow_nil? false
      public? true
    end
  end
end
