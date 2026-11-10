defmodule TeacherAssistant.Academics.TeacherUnavailability do
  @moduledoc """
  One blocked (day, period) of a teacher's week in an academic year (spec J3, T03):
  the teacher is not at school then. Entered by the censeur only (admin axis).
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Timetabling,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "teacher_unavailabilities"
    repo TeacherAssistant.Repo

    references do
      reference :academic_year,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :period,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :teacher, on_delete: :delete, index?: true
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read, :destroy, create: [:academic_year_id, :teacher_user_id, :day, :period_id]]

    read :for_year do
      argument :academic_year_id, :uuid, allow_nil?: false
      filter expr(academic_year_id == ^arg(:academic_year_id))
    end
  end

  policies do
    policy always() do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  changes do
    change {TeacherAssistant.Academics.YearOpen, path: []}, on: [:create, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :day, TeacherAssistant.Academics.DayOfWeek, allow_nil?: false, public?: true
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

    belongs_to :teacher, TeacherAssistant.Accounts.User do
      source_attribute :teacher_user_id
      allow_nil? false
      public? true
    end

    belongs_to :period, TeacherAssistant.Academics.Period do
      source_attribute :period_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_cell, [:academic_year_id, :teacher_user_id, :day, :period_id]
  end
end
