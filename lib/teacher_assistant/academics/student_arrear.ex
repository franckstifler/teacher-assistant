defmodule TeacherAssistant.Academics.StudentArrear do
  @moduledoc """
  A student's unpaid balance from a closed year, carried into this year's enrollment
  only when the school chose to (Fees 1, « Reporter les reliquats »).
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Fees,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "student_arrears"
    repo TeacherAssistant.Repo

    references do
      reference :enrollment,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :from_academic_year,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end

    check_constraints do
      check_constraint :amount, "student_arrears_amount_positive_check",
        check: "amount > 0",
        message: "must be positive"
    end
  end

  actions do
    defaults [:read, :destroy, create: [:enrollment_id, :from_academic_year_id, :amount]]
  end

  policies do
    policy action_type(:read) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :fees}
      authorize_if expr(enrollment.class_group.form_master_user_id == ^actor(:id))
    end

    policy action_type([:create, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :fees}
    end
  end

  validations do
    validate {TeacherAssistant.Academics.YearOpen, path: [:enrollment]}, on: [:create, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :amount, :integer, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :enrollment, TeacherAssistant.Academics.Enrollment do
      source_attribute :enrollment_id
      allow_nil? false
      public? true
    end

    belongs_to :from_academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :from_academic_year_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_arrear, [:enrollment_id, :from_academic_year_id]
  end
end
