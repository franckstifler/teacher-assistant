defmodule TeacherAssistant.Academics.TeachingAssignment do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics

  postgres do
    table "school_year_subject_teachers"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:classroom_id, :level_option_subject_id, :teacher_id]
    end

    update :update do
      primary? true
      accept [:classroom_id, :level_option_subject_id, :teacher_id]
    end
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :classroom, TeacherAssistant.Academics.Classroom, allow_nil?: false

    belongs_to :level_option_subject, TeacherAssistant.Academics.LevelOptionSubject,
      allow_nil?: false

    belongs_to :teacher, TeacherAssistant.Accounts.User, allow_nil?: false
  end

  identities do
    identity :unique_assignment,
             [:school_id, :classroom_id, :level_option_subject_id, :teacher_id]
  end
end
