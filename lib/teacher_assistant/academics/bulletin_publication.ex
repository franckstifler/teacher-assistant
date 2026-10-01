defmodule TeacherAssistant.Academics.BulletinPublication do
  @moduledoc """
  A class's report cards for a trimester or the year, published (spec I2). The
  `snapshot` is exactly what the report card, class results and print render
  (`TeacherAssistant.ReportCards.live_view/3`), stored as an Erlang term so decimals
  and atoms come back unchanged: nothing later changes a published card. A withdrawal
  keeps the row as history; republishing creates a new row.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Assessment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "bulletin_publications"
    repo TeacherAssistant.Repo

    identity_wheres_to_sql one_published_per_period: "status = 'published'"

    references do
      reference :class_group,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :academic_year,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full

      reference :term, on_delete: :delete
      reference :published_by, on_delete: :nilify
      reference :withdrawn_by, on_delete: :nilify
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    read :for_class do
      argument :class_group_id, :uuid, allow_nil?: false
      filter expr(class_group_id == ^arg(:class_group_id))
      prepare build(sort: [published_at: :desc], load: [:published_by, :withdrawn_by])
    end

    create :publish do
      accept [:class_group_id, :academic_year_id, :term_id, :period_kind, :period_key, :snapshot]
      change set_attribute(:status, :published)
      change set_attribute(:snapshot_version, 1)
      change set_attribute(:published_at, &DateTime.utc_now/0)
      change set_attribute(:published_by_user_id, actor(:id))
    end

    update :withdraw do
      require_atomic? false
      argument :reason, :string, allow_nil?: false
      validate attribute_equals(:status, :published)
      change set_attribute(:status, :withdrawn)
      change set_attribute(:withdrawal_reason, arg(:reason))
      change set_attribute(:withdrawn_at, &DateTime.utc_now/0)
      change set_attribute(:withdrawn_by_user_id, actor(:id))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action([:publish, :withdraw]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :period_kind, TeacherAssistant.Academics.PublicationPeriodKind,
      allow_nil?: false,
      public?: true

    # `Organization.period_param/1` of the period: "trim:<term id>" or "annee".
    attribute :period_key, :string, allow_nil?: false, public?: true

    attribute :status, TeacherAssistant.Academics.PublicationStatus,
      allow_nil?: false,
      default: :published,
      public?: true

    attribute :snapshot, :term, allow_nil?: false, public?: true
    attribute :snapshot_version, :integer, allow_nil?: false, default: 1, public?: true
    attribute :published_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :withdrawn_at, :utc_datetime_usec, public?: true
    attribute :withdrawal_reason, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :class_group, TeacherAssistant.Academics.ClassGroup do
      source_attribute :class_group_id
      allow_nil? false
      public? true
    end

    belongs_to :academic_year, TeacherAssistant.Academics.AcademicYear do
      source_attribute :academic_year_id
      allow_nil? false
      public? true
    end

    belongs_to :term, TeacherAssistant.Academics.Term do
      source_attribute :term_id
      public? true
    end

    belongs_to :published_by, TeacherAssistant.Accounts.User do
      source_attribute :published_by_user_id
      public? true
    end

    belongs_to :withdrawn_by, TeacherAssistant.Accounts.User do
      source_attribute :withdrawn_by_user_id
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_published_per_period, [:class_group_id, :period_key],
      where: expr(status == :published)
  end
end
