defmodule TeacherAssistant.Academics.Attendance do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource]

  postgres do
    table "attendances"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [:date, :status, :comment, :student_id, :classroom_id]
    defaults [:read, :destroy]

    create :create do
      primary? true
      upsert? true
      upsert_identity :unique_attendance
      upsert_fields [:status, :comment]
    end

    update :update do
      primary? true
    end

    read :by_classroom_and_date do
      argument :classroom_id, :uuid_v7, allow_nil?: false
      argument :date, :date, allow_nil?: false

      filter expr(classroom_id == ^arg(:classroom_id) and date == ^arg(:date))
    end

    read :by_classroom_date_range do
      argument :classroom_id, :uuid_v7, allow_nil?: false
      argument :start_date, :date, allow_nil?: false
      argument :end_date, :date, allow_nil?: false

      filter expr(
               classroom_id == ^arg(:classroom_id) and
                 date >= ^arg(:start_date) and
                 date <= ^arg(:end_date)
             )
    end
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :date, :date, public?: true, allow_nil?: false

    attribute :status, TeacherAssistant.Academics.AttendanceStatus,
      public?: true,
      allow_nil?: false,
      default: :present

    attribute :comment, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :student, TeacherAssistant.Academics.Student, allow_nil?: false, public?: true
    belongs_to :classroom, TeacherAssistant.Academics.Classroom, allow_nil?: false, public?: true
  end

  calculations do
    calculate :student_name, :string, expr(student.full_name)
  end

  identities do
    identity :unique_attendance, [:school_id, :student_id, :classroom_id, :date]
  end
end
