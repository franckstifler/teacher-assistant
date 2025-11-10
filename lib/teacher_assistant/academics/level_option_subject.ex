defmodule TeacherAssistant.Academics.LevelOptionSubject do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: TeacherAssistant.Academics

  @doc """
  Join table between LevelOption and Subject with additional attribute 'coefficient'.
  This resource allows associating subjects to level options along with a specific coefficient for each association.
  """

  postgres do
    table "levels_options_subjects"
    repo TeacherAssistant.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:coefficient, :level_option_id, :subject_id]
    end

    update :update do
      primary? true
      accept [:coefficient, :level_option_id, :subject_id]
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :coefficient, :integer, allow_nil?: false, public?: true, constraints: [min: 1]
  end

  relationships do
    belongs_to :level_option, TeacherAssistant.Academics.LevelOption, allow_nil?: false
    belongs_to :subject, TeacherAssistant.Academics.Subject, allow_nil?: false
  end

  identities do
    identity :name, [:level_option_id, :subject_id]
  end
end
