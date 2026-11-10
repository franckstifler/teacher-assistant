defmodule TeacherAssistant.Academics.FeeWarning do
  @moduledoc """
  « Avis de retard de paiement » (Fees 2): what a student owed toward the tranches due,
  per fee type, frozen when issued, with a pay-by date. Numbered `V<year>-000001`.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Fees,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "fee_warnings"
    repo TeacherAssistant.Repo

    custom_indexes do
      index [:enrollment_id], all_tenants?: true
    end

    references do
      # Fees 2: a printed paper outlives everything — an enrollment with one cannot be deleted.
      reference :enrollment,
        on_delete: :restrict,
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
    # Never edited: a mistake is cancelled (with a reason) and issued again.
    defaults [
      :read,
      create: [
        :enrollment_id,
        :academic_year_id,
        :issued_on,
        :pay_by,
        :lines,
        :total
        # seq, number, student_name, class_label and issued_by_user_id are set by
        # `FeeControl` under its numbering lock.
      ]
    ]

    update :cancel do
      require_atomic? false
      accept []

      argument :reason, :string,
        allow_nil?: false,
        constraints: [trim?: true, allow_empty?: false]

      validate attribute_equals(:status, :valid), message: "already cancelled"

      change set_attribute(:status, :cancelled)
      change set_attribute(:cancel_reason, arg(:reason))
      change set_attribute(:cancelled_at, &DateTime.utc_now/0)

      change fn changeset, context ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :cancelled_by_user_id,
          context.actor && context.actor.id
        )
      end
    end

    read :for_enrollment_ids do
      argument :enrollment_ids, {:array, :uuid}, allow_nil?: false
      filter expr(enrollment_id in ^arg(:enrollment_ids))
      prepare build(sort: [seq: :desc])
    end
  end

  policies do
    policy action_type(:read) do
      # Row rules name a user, not a membership: require an active one.
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :fees}
      # The class's form master reads them, like payments (control list, student card).
      authorize_if expr(enrollment.class_group.form_master_user_id == ^actor(:id))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :fees}
    end
  end

  changes do
    change {TeacherAssistant.Academics.YearOpen, path: []}, on: [:create, :update]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :seq, :integer, allow_nil?: false, public?: true
    attribute :number, :string, allow_nil?: false, public?: true
    attribute :issued_on, :date, allow_nil?: false, public?: true
    attribute :pay_by, :date, allow_nil?: false, public?: true

    attribute :lines, {:array, TeacherAssistant.Academics.FeeWarningLine},
      allow_nil?: false,
      default: [],
      public?: true

    attribute :total, :integer, allow_nil?: false, public?: true
    attribute :student_name, :string, allow_nil?: false, public?: true
    attribute :class_label, :string, allow_nil?: false, public?: true
    attribute :issued_by_user_id, :uuid, allow_nil?: true, public?: true

    attribute :status, TeacherAssistant.Academics.PaymentStatus,
      allow_nil?: false,
      default: :valid,
      public?: true

    attribute :cancelled_at, :utc_datetime_usec, allow_nil?: true, public?: true
    attribute :cancelled_by_user_id, :uuid, allow_nil?: true, public?: true
    attribute :cancel_reason, :string, allow_nil?: true, public?: true

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
    identity :unique_warning, [:academic_year_id, :seq]
  end
end
