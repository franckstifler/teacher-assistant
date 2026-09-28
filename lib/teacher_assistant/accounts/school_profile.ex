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
        :bulletin_group_subtotals?
      ]

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
