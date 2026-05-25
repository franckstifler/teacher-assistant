defmodule TeacherAssistant.Academics.TeachingLog do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics,
    extensions: [AshArchival.Resource]

  postgres do
    table "teaching_logs"
    repo TeacherAssistant.Repo
  end

  actions do
    default_accept [:progression_entry_id, :taught_on, :taught_hours, :notes]
    defaults [:create, :read, :update, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :school_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :taught_on, :date, public?: true, allow_nil?: false
    attribute :taught_hours, :decimal, public?: true, allow_nil?: false, default: Decimal.new("0")
    attribute :notes, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :school, TeacherAssistant.Academics.School
    belongs_to :progression_entry, TeacherAssistant.Academics.ProgressionEntry, allow_nil?: false
  end
end
