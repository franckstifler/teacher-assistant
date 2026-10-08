defmodule TeacherAssistant.Academics.Enrollment do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Enrollment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks

  postgres do
    table "enrollments"
    repo TeacherAssistant.Repo

    custom_indexes do
      # Composite-FK target: attribute multitenancy prefixes this to
      # (workspace_id, id), the unique key that tenant-matched references need.
      index [:id], unique: true
    end

    references do
      reference :student,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :class_group,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :academic_year,
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
        :status,
        :repeater,
        :student_id,
        :class_group_id,
        :academic_year_id
      ],
      update: [:status, :repeater, :class_group_id]
    ]

    read :for_class_group do
      argument :class_group_id, :uuid, allow_nil?: false
      filter expr(class_group_id == ^arg(:class_group_id))
      prepare build(load: [:student])
    end

    # Spec KLM1 (L3): the school-wide student list, class order then name, paginated.
    read :school_list do
      argument :academic_year_id, :uuid, allow_nil?: false
      argument :class_group_id, :uuid
      # Lower-cased by the caller.
      argument :query, :string
      # Élèves redesign: only students with no parent linked.
      argument :no_contact, :boolean, allow_nil?: false, default: false

      pagination offset?: true, countable: true, required?: false, default_limit: 50

      filter expr(academic_year_id == ^arg(:academic_year_id))
      filter expr(is_nil(^arg(:class_group_id)) or class_group_id == ^arg(:class_group_id))
      filter expr(not (^arg(:no_contact)) or not exists(student.guardian_links, true))

      filter expr(
               is_nil(^arg(:query)) or
                 contains(string_downcase(student.full_name), ^arg(:query)) or
                 string_downcase(student.matricule) == ^arg(:query)
             )

      prepare build(
                load: [:class_group, student: [primary_guardian_link: :guardian]],
                sort: [class_rank: :asc, class_label: :asc, student_name: :asc]
              )
    end

    read :for_student do
      argument :student_id, :uuid, allow_nil?: false
      filter expr(student_id == ^arg(:student_id))
      prepare build(load: [:class_group, :academic_year])
    end

    read :for_student_and_year do
      argument :student_id, :uuid, allow_nil?: false
      argument :academic_year_id, :uuid, allow_nil?: false

      filter expr(student_id == ^arg(:student_id) and academic_year_id == ^arg(:academic_year_id))
    end

    # Atomically creates a Student and its first Enrollment (the "new
    # student" path shared by the add_student/3 and enroll_new/3 flows).
    # `transaction? true` wraps the whole run in a DB transaction (Ash starts
    # it before `run` executes, per touches_resources below) — an Enrollment
    # insert failure (e.g. the unique_enrollment_per_year identity) rolls
    # back the just-created Student too, no orphan row.
    action :enroll_new, :map do
      argument :class_group_id, :uuid, allow_nil?: false
      argument :academic_year_id, :uuid, allow_nil?: false
      argument :repeater, :boolean, allow_nil?: false, default: false

      argument :status, TeacherAssistant.Academics.EnrollmentStatus,
        allow_nil?: false,
        default: :inscription

      argument :student_attrs, :map, allow_nil?: false

      # Spec 2026-10-08 §4: the main contact, written in the same transaction —
      # `%{guardian_id: id}` links a parent already on file, otherwise the map
      # is a new guardian's attributes. Guardian writes keep their own policies.
      argument :guardian, :map, allow_nil?: true

      touches_resources [
        TeacherAssistant.Academics.Student,
        TeacherAssistant.Academics.Guardian,
        TeacherAssistant.Academics.StudentGuardian
      ]

      transaction? true

      run fn input, scope ->
        args = input.arguments

        # Bootstrap write (spec §4.1 case 3): the new student has no class yet,
        # so no row rule could admit it. The sibling Enrollment create below is
        # authorized (admin or the class's form master) and a refusal rolls
        # this insert back with the transaction.
        with {:ok, student} <-
               TeacherAssistant.Academics.Student
               |> Ash.Changeset.for_create(:create, args.student_attrs,
                 tenant: input.tenant,
                 authorize?: false
               )
               |> Ash.create(),
             {:ok, enrollment} <-
               __MODULE__
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   student_id: student.id,
                   class_group_id: args.class_group_id,
                   academic_year_id: args.academic_year_id,
                   repeater: args.repeater,
                   status: args.status
                 },
                 scope: scope
               )
               |> Ash.create(),
             :ok <- attach_guardian(student, args[:guardian], scope) do
          {:ok, %{student: student, enrollment: enrollment}}
        end
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    policy action(:enroll_new) do
      authorize_if {Checks.SchoolRole, any_of: :member}
    end

    # Update/destroy are checked against the original record, so a transfer is
    # decided by the source class.
    policy action_type([:create, :update, :destroy]) do
      # Row rules name a user, not a membership: require an active one.
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if expr(class_group.form_master_user_id == ^actor(:id))
    end
  end

  validations do
    validate {TeacherAssistant.Academics.YearOpen, path: []}, on: [:create, :update, :destroy]

    # A move into (or out of) a class is checked against that class's year too.
    validate {TeacherAssistant.Academics.YearOpen, path: [:class_group]},
      on: [:create, :update, :destroy]
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :status, TeacherAssistant.Academics.EnrollmentStatus,
      allow_nil?: false,
      default: :inscription,
      public?: true

    attribute :repeater, :boolean, allow_nil?: false, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :student, TeacherAssistant.Academics.Student do
      source_attribute :student_id
      allow_nil? false
      public? true
    end

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

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  calculations do
    calculate :class_rank, :integer, expr(class_group.level_rank)
    calculate :class_label, :string, expr(class_group.label)
    calculate :student_name, :string, expr(string_downcase(student.full_name))
  end

  identities do
    identity :unique_enrollment_per_year, [:student_id, :academic_year_id]
  end

  alias TeacherAssistant.Academics.{Guardian, StudentGuardian}

  defp attach_guardian(_student, nil, _scope), do: :ok

  defp attach_guardian(student, %{guardian_id: id}, scope) do
    with {:ok, guardian} <- Ash.get(Guardian, id, scope: scope),
         do: link_guardian(student, guardian, scope)
  end

  defp attach_guardian(student, attrs, scope) when is_map(attrs) do
    with {:ok, guardian} <-
           Guardian |> Ash.Changeset.for_create(:create, attrs, scope: scope) |> Ash.create(),
         do: link_guardian(student, guardian, scope)
  end

  defp link_guardian(student, guardian, scope) do
    StudentGuardian
    |> Ash.Changeset.for_create(:link, %{student_id: student.id, guardian_id: guardian.id},
      scope: scope
    )
    |> Ash.create()
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end
end
