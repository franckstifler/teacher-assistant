defmodule TeacherAssistant.Accounts.SchoolProfile do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "school_profiles"
    repo TeacherAssistant.Repo

    references do
      reference :workspace, on_delete: :delete, index?: true
      reference :owner_user, index?: true
    end

    check_constraints do
      check_constraint :default_max_score, "school_profiles_default_max_positive_check",
        check: "default_max_score > 0",
        message: "must be positive"
    end
  end

  actions do
    defaults [:read, :destroy]

    read :for_workspace do
      argument :workspace_id, :uuid, allow_nil?: false
      get? true
      filter expr(workspace_id == ^arg(:workspace_id))
    end

    read :unverified do
      filter expr(verification_status == :unverified)
      prepare build(load: [:workspace, :owner_user], sort: [inserted_at: :asc])
    end

    create :create do
      accept [
        :workspace_id,
        :owner_user_id,
        :short_name,
        :school_type,
        :subsystem,
        :sector,
        :region,
        :department,
        :town,
        :phone,
        :email,
        :address,
        :head_name,
        :motto,
        :registration_number,
        :logo_path
      ]
    end

    update :update do
      require_atomic? false

      accept [
        :short_name,
        :school_type,
        :subsystem,
        :sector,
        :region,
        :department,
        :town,
        :phone,
        :email,
        :address,
        :head_name,
        :motto,
        :registration_number,
        :logo_path,
        :class_coefficients_allowed?,
        :bulletin_group_subtotals?,
        :trimester_average_rule,
        :annual_average_rule,
        :average_rounding,
        :shared_ranks?,
        :absence_rule,
        :default_max_score,
        :entry_grace_days,
        :appreciation_bands,
        :felicitations_min,
        :encouragements_min,
        :tableau_honneur_min,
        :avertissement_travail_below,
        :blame_travail_below,
        :distinctions_require_all_passed?,
        :distinctions_require_conduct?,
        :passage_min,
        :rachat_min,
        :exclusion_below,
        :one_repeat_per_cycle?,
        :exclusion_on_conduct?,
        :exclusion_absence_hours,
        :bulletin_language,
        :bulletin_elements,
        :grade_scale,
        :lesson_days,
        :wednesday_afternoon_off?,
        :default_lesson_minutes,
        :statutory_hours
      ]

      validate TeacherAssistant.Accounts.SchoolProfile.ValidateAppreciations
      validate TeacherAssistant.Accounts.SchoolProfile.ValidatePassage
      validate TeacherAssistant.Accounts.SchoolProfile.ValidateGradeScale

      change fn changeset, _context ->
        if Ash.Changeset.get_data(changeset, :verification_status) == :rejected do
          changeset
          |> Ash.Changeset.change_attribute(:verification_status, :unverified)
          |> Ash.Changeset.change_attribute(:rejection_reason, nil)
          |> Ash.Changeset.change_attribute(:verified_at, nil)
          |> Ash.Changeset.change_attribute(:verified_by_user_id, nil)
        else
          changeset
        end
      end
    end

    # Spec KLM2: the SG edits these too, so not through the admin-only `:update`.
    update :update_school_life do
      accept [
        :late_as_absence_minutes,
        :justification_deadline_days,
        :absence_alert_hours,
        :conduct_points_per_absence_hour,
        :conduct_points_per_late,
        :sanction_points,
        :sanction_types_in_use
      ]
    end

    update :verify do
      accept [:verified_by_user_id]
      change set_attribute(:verification_status, :verified)
      change set_attribute(:verified_at, &DateTime.utc_now/0)
      change set_attribute(:rejection_reason, nil)
    end

    update :reject do
      accept [:verified_by_user_id, :rejection_reason]
      change set_attribute(:verification_status, :rejected)
      change set_attribute(:verified_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy action(:unverified) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action([:read, :for_workspace]) do
      authorize_if actor_attribute_equals(:role, :admin)

      authorize_if expr(
                     exists(
                       workspace.school_memberships,
                       user_id == ^actor(:id) and active == true
                     )
                   )
    end

    policy action(:update) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end

    policy action(:update_school_life) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
    end

    policy action([:verify, :reject]) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :short_name, :string, public?: true
    attribute :school_type, TeacherAssistant.Accounts.SchoolType, allow_nil?: false, public?: true

    attribute :subsystem, TeacherAssistant.Accounts.SchoolSubsystem,
      allow_nil?: false,
      public?: true

    attribute :sector, TeacherAssistant.Accounts.SchoolSector, allow_nil?: false, public?: true
    attribute :region, TeacherAssistant.Accounts.CameroonRegion, allow_nil?: false, public?: true
    attribute :department, :string, public?: true
    attribute :town, :string, allow_nil?: false, public?: true
    attribute :phone, :string, public?: true
    attribute :email, :string, public?: true
    attribute :address, :string, public?: true
    attribute :head_name, :string, public?: true
    attribute :motto, :string, public?: true
    attribute :registration_number, :string, public?: true
    attribute :logo_path, :string, public?: true

    attribute :class_coefficients_allowed?, :boolean,
      allow_nil?: false,
      default: true,
      public?: true

    attribute :bulletin_group_subtotals?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :trimester_average_rule, TeacherAssistant.Academics.TrimesterAverageRule,
      allow_nil?: false,
      default: :mean_of_sequences,
      public?: true

    attribute :annual_average_rule, TeacherAssistant.Academics.AnnualAverageRule,
      allow_nil?: false,
      default: :mean_of_sequences,
      public?: true

    attribute :average_rounding, TeacherAssistant.Academics.AverageRounding,
      allow_nil?: false,
      default: :hundredth,
      public?: true

    attribute :shared_ranks?, :boolean, allow_nil?: false, default: true, public?: true

    attribute :absence_rule, TeacherAssistant.Academics.AbsenceRule,
      allow_nil?: false,
      default: :zero,
      public?: true

    attribute :default_max_score, :decimal,
      allow_nil?: false,
      default: Decimal.new(20),
      public?: true

    # "fin de séquence + N jours": the grade-entry deadline when a séquence sets none (spec D3b).
    attribute :entry_grace_days, :integer,
      allow_nil?: false,
      default: 5,
      public?: true,
      constraints: [min: 0, max: 30]

    # Spec I1: the school's appreciation scale; nil = the default scale.
    attribute :appreciation_bands, {:array, TeacherAssistant.Accounts.AppreciationBand},
      public?: true

    # Spec I1: distinction and work-warning thresholds (/20); nil = switched off.
    attribute :felicitations_min, :decimal, default: Decimal.new(16), public?: true
    attribute :encouragements_min, :decimal, default: Decimal.new(14), public?: true
    attribute :tableau_honneur_min, :decimal, default: Decimal.new(12), public?: true
    attribute :avertissement_travail_below, :decimal, default: Decimal.new(8), public?: true
    attribute :blame_travail_below, :decimal, default: Decimal.new(6), public?: true

    attribute :distinctions_require_all_passed?, :boolean,
      allow_nil?: false,
      default: true,
      public?: true

    attribute :distinctions_require_conduct?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    # Spec I4: passage rules for the annual council's proposals; nil = rule off.
    attribute :passage_min, :decimal, allow_nil?: false, default: Decimal.new(10), public?: true
    attribute :rachat_min, :decimal, default: Decimal.new("9.5"), public?: true
    attribute :exclusion_below, :decimal, default: Decimal.new(7), public?: true

    attribute :one_repeat_per_cycle?, :boolean,
      allow_nil?: false,
      default: true,
      public?: true

    attribute :exclusion_on_conduct?, :boolean,
      allow_nil?: false,
      default: true,
      public?: true

    attribute :exclusion_absence_hours, :integer, default: 60, public?: true

    # Spec I5: the printed report card's template.
    attribute :bulletin_language, TeacherAssistant.Academics.BulletinLanguage,
      allow_nil?: false,
      default: :by_class,
      public?: true

    # nil = `BulletinElement.defaults/0`; [] = no optional element.
    attribute :bulletin_elements, {:array, TeacherAssistant.Academics.BulletinElement},
      public?: true

    # nil/[] = `BulletinTemplate.default_grade_scale/0`.
    attribute :grade_scale, {:array, TeacherAssistant.Accounts.GradeBand}, public?: true

    # Spec J1: the school calendar. nil lesson days = Monday to Saturday.
    attribute :lesson_days, {:array, TeacherAssistant.Academics.DayOfWeek}, public?: true

    attribute :wednesday_afternoon_off?, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :default_lesson_minutes, :integer,
      allow_nil?: false,
      default: 50,
      public?: true,
      constraints: [min: 1, max: 240]

    # Spec J2: the teaching load a full-time teacher owes per week.
    attribute :statutory_hours, :integer,
      allow_nil?: false,
      default: 18,
      public?: true,
      constraints: [min: 1, max: 40]

    # Spec KLM2: attendance and discipline settings (« Assiduité & discipline »).
    attribute :late_as_absence_minutes, :integer, public?: true, constraints: [min: 1, max: 240]

    attribute :justification_deadline_days, :integer,
      public?: true,
      constraints: [min: 1, max: 60]

    attribute :absence_alert_hours, :integer,
      allow_nil?: false,
      default: 10,
      public?: true,
      constraints: [min: 1, max: 200]

    attribute :conduct_points_per_absence_hour, :decimal,
      allow_nil?: false,
      default: Decimal.new("0.5"),
      public?: true,
      constraints: [min: 0, max: 5]

    attribute :conduct_points_per_late, :decimal,
      allow_nil?: false,
      default: Decimal.new("0.25"),
      public?: true,
      constraints: [min: 0, max: 5]

    # nil = `SanctionPoints` defaults.
    attribute :sanction_points, TeacherAssistant.Accounts.SanctionPoints, public?: true

    # nil = every sanction type.
    attribute :sanction_types_in_use, {:array, TeacherAssistant.Academics.SanctionType},
      public?: true

    attribute :verification_status, TeacherAssistant.Accounts.SchoolVerificationStatus,
      allow_nil?: false,
      default: :unverified,
      public?: true

    attribute :verified_at, :utc_datetime_usec, public?: true
    attribute :verified_by_user_id, :uuid, public?: true
    attribute :rejection_reason, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    belongs_to :owner_user, TeacherAssistant.Accounts.User do
      source_attribute :owner_user_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_workspace, [:workspace_id]
  end
end
