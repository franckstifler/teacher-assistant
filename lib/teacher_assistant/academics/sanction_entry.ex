defmodule TeacherAssistant.Academics.SanctionEntry do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Discipline,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "sanction_entries"
    repo TeacherAssistant.Repo

    references do
      reference :enrollment,
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
      create: [
        :type,
        :date,
        :reason,
        :duration_days,
        :issued_by_user_id,
        :enrollment_id
      ],
      update: [
        :type,
        :date,
        :reason,
        :duration_days,
        :issued_by_user_id
      ]
    ]

    read :for_class_in_range do
      argument :class_group_id, :uuid, allow_nil?: false
      argument :first, :date, allow_nil?: false
      argument :last, :date, allow_nil?: false

      filter expr(
               enrollment.class_group_id == ^arg(:class_group_id) and date >= ^arg(:first) and
                 date <= ^arg(:last)
             )

      prepare build(load: [enrollment: :student], sort: [date: :desc])
    end

    read :for_enrollment_in_range do
      argument :enrollment_id, :uuid, allow_nil?: false
      argument :first, :date, allow_nil?: false
      argument :last, :date, allow_nil?: false

      filter expr(
               enrollment_id == ^arg(:enrollment_id) and date >= ^arg(:first) and
                 date <= ^arg(:last)
             )

      prepare build(load: [enrollment: :student], sort: [date: :desc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :conduct}
      authorize_if expr(enrollment.class_group.form_master_user_id == ^actor(:id))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :conduct}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :type, TeacherAssistant.Academics.SanctionType, allow_nil?: false, public?: true

    attribute :date, :date, allow_nil?: false, public?: true
    attribute :reason, :string, allow_nil?: true, public?: true
    attribute :duration_days, :integer, allow_nil?: true, public?: true
    attribute :issued_by_user_id, :uuid, allow_nil?: true, public?: true

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
  end
end
