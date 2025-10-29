defmodule TeacherAssistant.Academics.School do
  use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: TeacherAssistant.Academics

  postgres do
    repo TeacherAssistant.Repo
    table "schools"
  end

  actions do
    default_accept [:name, :abbreviation, :type, :sub_system, :description]
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
    identity :unique_name, [:name]
  end
end

defimpl Ash.ToTenant, for: TeacherAssistant.Academics.School do
  def to_tenant(%{id: id}, _resource), do: id
end
