defmodule TeacherAssistant.Academics.Enrollment do
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Enrollment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

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

    read :for_student_and_year do
      argument :student_id, :uuid, allow_nil?: false
      argument :academic_year_id, :uuid, allow_nil?: false

      filter expr(student_id == ^arg(:student_id) and academic_year_id == ^arg(:academic_year_id))
    end

    # Atomically creates a Student and its first Enrollment (the "new
    # student" path shared by the add_student/2 and enroll_new/2 flows).
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

      touches_resources [TeacherAssistant.Academics.Student]
      transaction? true

      run fn input, _ctx ->
        args = input.arguments

        with {:ok, student} <-
               TeacherAssistant.Academics.Student
               |> Ash.Changeset.for_create(:create, args.student_attrs)
               |> Ash.Changeset.set_tenant(input.tenant)
               |> Ash.create(),
             {:ok, enrollment} <-
               __MODULE__
               |> Ash.Changeset.for_create(:create, %{
                 student_id: student.id,
                 class_group_id: args.class_group_id,
                 academic_year_id: args.academic_year_id,
                 repeater: args.repeater,
                 status: args.status
               })
               |> Ash.Changeset.set_tenant(input.tenant)
               |> Ash.create() do
          {:ok, %{student: student, enrollment: enrollment}}
        end
      end
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
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

  identities do
    identity :unique_enrollment_per_year, [:student_id, :academic_year_id]
  end
end
