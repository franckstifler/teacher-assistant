defmodule TeacherAssistant.Academics.Learner do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "learners"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:first_name, :last_name, :identifier, :personal_classroom_id],
      update: [:first_name, :last_name, :identifier]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :first_name, :string, allow_nil?: false, public?: true
    attribute :last_name, :string, allow_nil?: false, public?: true
    attribute :identifier, :string, public?: true
    timestamps()
  end

  relationships do
    belongs_to :personal_classroom, TeacherAssistant.Academics.PersonalClassroom do
      allow_nil? false
      public? true
    end

    has_many :attendance_records, TeacherAssistant.Academics.AttendanceRecord
  end

  calculations do
    calculate :full_name, :string, expr(first_name <> " " <> last_name), public?: true
  end
end
