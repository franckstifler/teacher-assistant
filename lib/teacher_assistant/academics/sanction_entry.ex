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
        :duration_hours,
        :issued_by_user_id,
        :enrollment_id
      ],
      update: [
        :type,
        :date,
        :reason,
        :duration_days,
        :duration_hours,
        :issued_by_user_id
      ]
    ]

    # V06: the school told the parents about this sanction, today, by the actor.
    update :mark_parents_notified do
      accept []
      require_atomic? false

      change fn changeset, context ->
        changeset
        |> Ash.Changeset.force_change_attribute(
          :parents_notified_on,
          TeacherAssistant.Academics.Reference.today()
        )
        |> Ash.Changeset.force_change_attribute(
          :parents_notified_by_user_id,
          context.actor && context.actor.id
        )
      end
    end

    # The school's latest sanctions (spec G, "Sanctions récentes").
    read :recent do
      prepare build(
                sort: [date: :desc, inserted_at: :desc],
                limit: 5,
                load: [enrollment: [:student, :class_group]]
              )
    end

    # Sanctions whose parents have not been told yet (spec G, KPI "Sanctions à notifier").
    read :parents_to_notify do
      filter expr(is_nil(parents_notified_on))
    end

    # Spec KLM4: the SG's school-wide list, newest first, paginated.
    read :school_list do
      argument :academic_year_id, :uuid, allow_nil?: false
      argument :class_group_id, :uuid
      argument :type, TeacherAssistant.Academics.SanctionType
      argument :to_notify, :boolean, default: false

      pagination offset?: true, countable: true, required?: false, default_limit: 50

      filter expr(enrollment.academic_year_id == ^arg(:academic_year_id))

      filter expr(
               is_nil(^arg(:class_group_id)) or enrollment.class_group_id == ^arg(:class_group_id)
             )

      filter expr(is_nil(^arg(:type)) or type == ^arg(:type))
      filter expr(^arg(:to_notify) == false or is_nil(parents_notified_on))

      prepare build(
                sort: [date: :desc, inserted_at: :desc],
                load: [enrollment: [:class_group, student: [primary_guardian_link: :guardian]]]
              )
    end

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
      # Row rules name a user, not a membership: require an active one.
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
      authorize_if expr(enrollment.class_group.form_master_user_id == ^actor(:id))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :conduct}
    end
  end

  validations do
    validate {TeacherAssistant.Academics.YearOpen, path: [:enrollment]},
      on: [:create, :update, :destroy]

    # Vie scolaire redesign §1.3: a consigne is given in hours.
    validate present(:duration_hours),
      where: [attribute_equals(:type, :consigne)],
      on: [:create]
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

    attribute :duration_hours, :integer,
      allow_nil?: true,
      public?: true,
      constraints: [min: 1, max: 40]

    attribute :issued_by_user_id, :uuid, allow_nil?: true, public?: true
    attribute :parents_notified_on, :date, allow_nil?: true, public?: true
    attribute :parents_notified_by_user_id, :uuid, allow_nil?: true, public?: true

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
