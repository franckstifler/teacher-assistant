defmodule TeacherAssistant.Academics.LevelOption do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics

  postgres do
    repo TeacherAssistant.Repo
    table "levels_options"
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
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
    belongs_to :option, TeacherAssistant.Academics.Option, allow_nil?: false
    belongs_to :level, TeacherAssistant.Academics.Level, allow_nil?: false
  end

  calculations do
    calculate :full_name, :string, expr(level.name <> " " <> option.name)
  end

  identities do
    identity :level_option, [:level_id, :option_id]
  end
end
