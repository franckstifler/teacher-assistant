defmodule TeacherAssistant.Academics.TeachingContext do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "teaching_contexts"
    repo TeacherAssistant.Repo

    custom_indexes do
      index [:workspace_id, :academic_year_id, :subject, :level, :serie],
        unique: true,
        nulls_distinct: false,
        where: "teacher_user_id IS NULL",
        name: "teaching_contexts_unique_personal_context",
        message: "a context for this subject and level already exists"

      index [:workspace_id, :academic_year_id, :class_group_id, :subject],
        unique: true,
        where: "teacher_user_id IS NOT NULL",
        name: "teaching_contexts_unique_school_assignment",
        message: "this class already has a teacher for this subject"
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :subject,
        :level,
        :serie,
        :subsystem,
        :weekly_hours,
        :coefficient,
        :workspace_id,
        :academic_year_id,
        :teacher_user_id,
        :class_group_id
      ],
      update: [
        :subject,
        :level,
        :serie,
        :subsystem,
        :weekly_hours,
        :coefficient,
        :class_group_id,
        :teacher_user_id
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
    attribute :subject, :string, allow_nil?: false, public?: true
    attribute :level, :string, allow_nil?: false, public?: true
    attribute :serie, :string, allow_nil?: true, public?: true

    attribute :subsystem, TeacherAssistant.Academics.Subsystem,
      allow_nil?: false,
      default: :francophone,
      public?: true

    attribute :weekly_hours, :integer, default: 4, public?: true

    attribute :coefficient, :decimal,
      allow_nil?: false,
      default: Decimal.new(1),
      public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? true
      public? true
    end

    belongs_to :teacher, TeacherAssistant.Accounts.User do
      source_attribute :teacher_user_id
      allow_nil? true
      public? true
    end
  end
end
