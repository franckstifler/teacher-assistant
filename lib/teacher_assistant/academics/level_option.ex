defmodule TeacherAssistant.Academics.LevelOption do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics

  postgres do
    repo TeacherAssistant.Repo
    table "levels_options"
  end

  actions do
    default_accept [:level_id, :option_id]
    defaults [:read, :destroy, create: :*, update: :*]

    update :manage_subjects do
      require_atomic? false
      argument :subjects, {:array, :map}, default: []
      argument :selected_subjects, {:array, :uuid_v7}, default: []

      change manage_relationship(:subjects, :subjects, type: :direct_control)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :option, TeacherAssistant.Academics.Option, allow_nil?: false, public?: true
    belongs_to :level, TeacherAssistant.Academics.Level, allow_nil?: false, public?: true
    has_many :subjects, TeacherAssistant.Academics.LevelOptionSubject
  end

  calculations do
    calculate :full_name, :string, expr(level.name <> " " <> option.name)
  end

  identities do
    identity :level_option, [:level_id, :option_id]
  end
end
