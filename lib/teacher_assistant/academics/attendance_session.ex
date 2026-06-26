defmodule TeacherAssistant.Academics.AttendanceSession do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "attendance_sessions"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:date, :notes, :personal_classroom_id],
      update: [:date, :notes]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :date, :date, allow_nil?: false, public?: true
    attribute :notes, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :personal_classroom, TeacherAssistant.Academics.PersonalClassroom do
      allow_nil? false
      public? true
    end

    has_many :attendance_records, TeacherAssistant.Academics.AttendanceRecord
  end

  identities do
    identity :unique_classroom_date, [:personal_classroom_id, :date]
  end
end
