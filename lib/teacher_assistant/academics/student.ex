defmodule TeacherAssistant.Academics.Student do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Academics,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "students"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:full_name, :sex, :matricule, :repeater, :class_group_id],
      update: [:full_name, :sex, :matricule, :repeater]
    ]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :full_name, :string, allow_nil?: false, public?: true
    attribute :sex, TeacherAssistant.Academics.Sex, allow_nil?: false, public?: true
    attribute :matricule, :string, allow_nil?: true, public?: true
    attribute :repeater, :boolean, allow_nil?: false, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end
  end
end
