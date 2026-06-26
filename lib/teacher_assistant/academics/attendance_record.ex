defmodule TeacherAssistant.Academics.AttendanceRecord do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "attendance_records"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [:status, :note, :attendance_session_id, :learner_id]
    defaults [:read, :destroy]

    create :create do
      primary? true
      upsert? true
      upsert_identity :unique_session_learner
      upsert_fields [:status, :note]
    end

    update :update do
      primary? true
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :status, TeacherAssistant.Academics.AttendanceStatus,
      allow_nil?: false,
      default: :present,
      public?: true

    attribute :note, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :attendance_session, TeacherAssistant.Academics.AttendanceSession do
      allow_nil? false
      public? true
    end

    belongs_to :learner, TeacherAssistant.Academics.Learner do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_session_learner, [:attendance_session_id, :learner_id]
  end
end
