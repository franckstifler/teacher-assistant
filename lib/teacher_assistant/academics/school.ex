defmodule TeacherAssitant.Academics.School do
  use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: TeacherAssitant.Academics

  postgres do
    repo TeacherAssitant.Repo
    table "schools"
  end

  actions do
    default_accept [:name, :abbreviation, :type, :sub_system, :descripiton]
    defaults [:create, :update, :read, :destroy]
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :abbreviation, :string, public?: true
    attribute :type, TeacherAssistant.Academics.Enums.SchoolType, public?: true
    attribute :sub_system, TeacherAssistant.Academics.Enums.SchoolSubsystem, public?: true
    attribute :description, :string, public?: true

    timestamps()
  end

  identities do
    identity :name, [:name]
  end
end
