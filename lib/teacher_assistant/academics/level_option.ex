defmodule Ap.Academics.LevelOption do
  use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: Ap.Academics

  postgres do
    repo Ap.Repo
    table "levels_options"
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :option, Ap.Academics.Option, allow_nil?: false, primary_key?: true
    belongs_to :level, Ap.Academics.Level, allow_nil?: false, primary_key?: true
  end

  calculations do
    calculate :full_name, :string, expr(level.name <> " " <> option.name)
  end
end
