defmodule TeacherAssistant.Academics.FeeSendOut do
  @moduledoc """
  A student the bursar sent out of class for unpaid fees on one day (Fees 2). It lasts
  that day only; the day's roll calls taken afterwards show « Renvoyé pour frais ».
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Fees,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "fee_send_outs"
    repo TeacherAssistant.Repo

    custom_indexes do
      index [:enrollment_id], all_tenants?: true
    end

    references do
      reference :enrollment,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :academic_year,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:enrollment_id, :academic_year_id, :date, :recorded_by_user_id]
    ]

    read :on_date do
      argument :enrollment_ids, {:array, :uuid}, allow_nil?: false
      argument :date, :date, allow_nil?: false
      filter expr(enrollment_id in ^arg(:enrollment_ids) and date == ^arg(:date))
    end
  end

  policies do
    # Teachers read them: the roll call shows who was sent home.
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :fees}
    end
  end

  changes do
    change {TeacherAssistant.Academics.YearOpen, path: []}, on: [:create, :update, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :date, :date, allow_nil?: false, public?: true
    attribute :recorded_by_user_id, :uuid, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :enrollment, TeacherAssistant.Academics.Enrollment do
      source_attribute :enrollment_id
      allow_nil? false
      public? true
    end

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
  end

  identities do
    identity :unique_per_day, [:enrollment_id, :date]
  end
end
