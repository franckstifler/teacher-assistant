defmodule TeacherAssistant.Academics.SubjectCoefficient do
  @moduledoc """
  One enabled cell of the school's coefficient grid: a subject's coefficient at a
  level (and, for streamed 2nd-cycle levels, a série). A missing row means the
  subject is not taught there. A blank série applies to every série that has no
  cell of its own (see `CoefficientRules.resolve/2`).
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "subject_coefficients"
    repo TeacherAssistant.Repo

    references do
      reference :subject,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end

    check_constraints do
      check_constraint :coefficient, "subject_coefficients_positive_check",
        check: "coefficient > 0",
        message: "must be positive"
    end
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [:subject_id, :subsystem, :level, :serie, :coefficient],
      update: [:coefficient]
    ]
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :subsystem, TeacherAssistant.Academics.Subsystem,
      allow_nil?: false,
      public?: true

    attribute :level, :string, allow_nil?: false, public?: true
    attribute :serie, :string, allow_nil?: true, public?: true
    attribute :coefficient, :decimal, allow_nil?: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :subject, TeacherAssistant.Academics.Subject do
      source_attribute :subject_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    # `subject_id` is already tenant-unique, so the index needs no workspace prefix
    # (which also keeps the generated migration's statements in a valid order).
    identity :unique_cell, [:subject_id, :subsystem, :level, :serie],
      nils_distinct?: false,
      all_tenants?: true
  end
end
