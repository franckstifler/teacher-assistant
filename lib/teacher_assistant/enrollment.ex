defmodule TeacherAssistant.Enrollment do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

  alias TeacherAssistant.Academics.{
    AcademicYear,
    ClassGroup,
    Enrollment,
    Guardian,
    Student,
    StudentGuardian
  }

  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Accounts.Checks
  alias TeacherAssistant.Scope

  resources do
    resource ClassGroup do
      define :update_class_group, action: :update
    end

    resource Student do
      define :update_student, action: :update
      define :set_student_photo, action: :set_photo
      define :remove_student_photo, action: :remove_photo
    end

    resource Enrollment do
      define :update_enrollment, action: :update
    end

    resource TeacherAssistant.Academics.Guardian
    resource TeacherAssistant.Academics.StudentGuardian
  end

  authorization do
    authorize :by_default
  end

  @doc """
  Navigation gate — **not a security boundary**: whether the scope may open a
  class's management pages (roster, results, bulletins, timetable, register).
  Those pages read membership-readable data; the sensitive reads on them are
  policy-enforced regardless. True for the admin axis and for the class's form
  master, both with a fresh active membership.
  """
  def class_manager?(
        %Scope{current_user: %{id: uid} = user, current_workspace: %{id: ws_id}},
        %ClassGroup{} = cg
      ) do
    Checks.SchoolRole.holds?(user, ws_id, :admin) or
      (cg.form_master_user_id == uid and Checks.SchoolRole.holds?(user, ws_id, :member))
  end

  def class_manager?(_scope, _cg), do: false

  @doc "Whether the scope may create and delete classes (admin axis)."
  def can_manage_classes?(scope), do: Ash.can?({ClassGroup, :create}, scope)

  # --- ClassGroup ------------------------------------------------------------

  def create_class_group(%Scope{} = scope, %AcademicYear{} = year, attrs) do
    if year.workspace_id != scope.current_workspace.id do
      {:error, :workspace_mismatch}
    else
      attrs =
        attrs
        |> Map.put(:academic_year_id, year.id)
        |> Map.put_new(:subsystem, :francophone)

      ClassGroup
      |> Ash.Changeset.for_create(:create, attrs, scope: scope)
      |> Ash.create()
    end
  end

  def list_class_groups(%Scope{} = scope, %AcademicYear{id: year_id}, opts \\ []) do
    ClassGroup
    |> Ash.Query.for_read(:for_workspace_and_year, %{academic_year_id: year_id}, scope: scope)
    |> Ash.Query.load(opts[:load] || [])
    |> Ash.read!()
  end

  def fetch_owned_class_group(%Scope{} = scope, id) do
    ClassGroup
    |> Ash.Query.for_read(:owned, %{id: id}, scope: scope)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  @doc """
  Deletes a class group, refusing when it has enrollments or teacher
  assignments still attached (would orphan rows across the Enrollment and
  Curriculum domains).
  """
  def delete_class_group(%Scope{} = scope, %ClassGroup{id: id} = cg) do
    has_enrollments =
      Enrollment
      |> Ash.Query.for_read(:for_class_group, %{class_group_id: id}, scope: scope)
      |> Ash.read!() != []

    has_assignments =
      TeachingContext
      |> Ash.Query.filter(class_group_id == ^id)
      |> Ash.read!(scope: scope) != []

    if has_enrollments or has_assignments do
      {:error, :has_data}
    else
      case Ash.destroy(cg, scope: scope) do
        :ok -> :ok
        {:error, error} -> {:error, error}
      end
    end
  end

  @doc """
  Sets (or clears, with `user_id: nil`) `cg`'s form master. A non-`nil`
  `user_id` must name an active `SchoolMembership` in `cg`'s own workspace —
  `User` isn't multitenant, so `ClassGroup.FormMasterIsMember` is the tenant
  check for it, on every write of the field.
  """
  def set_form_master(%Scope{} = scope, %ClassGroup{} = cg, user_id) do
    cg
    |> Ash.Changeset.for_update(:update, %{form_master_user_id: user_id}, scope: scope)
    |> Ash.update()
  end

  @doc """
  Sets (or clears, with nil) the class's home room (spec J3); `{:error, :invalid}` for a
  room that is not an active room of the school.
  """
  def set_home_room(%Scope{} = scope, %ClassGroup{} = cg, room_id) do
    if is_nil(room_id) or active_room?(scope, room_id) do
      cg
      |> Ash.Changeset.for_update(:update, %{home_room_id: room_id}, scope: scope)
      |> Ash.update()
    else
      {:error, :invalid}
    end
  end

  defp active_room?(scope, room_id),
    do:
      match?(
        {:ok, %{active?: true}},
        Ash.get(TeacherAssistant.Academics.Room, room_id, scope: scope)
      )

  @doc "Enrolled students per class of the year: `%{class_group_id => count}` (spec J3), one query."
  def class_sizes(%Scope{} = scope, %AcademicYear{} = year) do
    scope
    |> list_class_groups(year, load: [:enrollment_count])
    |> Map.new(&{&1.id, &1.enrollment_count})
  end

  @doc "Sets (or clears, with nil) the class's own maximum size."
  def set_class_max_size(%Scope{} = scope, %ClassGroup{} = cg, max_size) do
    cg
    |> Ash.Changeset.for_update(:update, %{max_size: max_size}, scope: scope)
    |> Ash.update()
  end

  def form_master(%Scope{}, %ClassGroup{form_master_user_id: nil}), do: nil

  def form_master(%Scope{} = scope, %ClassGroup{form_master_user_id: uid}) do
    case Ash.get(TeacherAssistant.Accounts.User, uid, scope: scope) do
      {:ok, user} -> user
      _ -> nil
    end
  end

  def list_form_master_classes(%Scope{} = scope, %AcademicYear{id: year_id}) do
    ClassGroup
    |> Ash.Query.for_read(
      :for_form_master,
      %{
        academic_year_id: year_id,
        form_master_user_id: scope.current_user.id
      },
      scope: scope
    )
    |> Ash.read!()
  end

  # --- Student -----------------------------------------------------------

  def delete_student(%Scope{} = scope, %Student{} = s),
    do: Ash.destroy(s, scope: scope)

  def fetch_owned_student(%Scope{} = scope, id) do
    Student
    |> Ash.Query.for_read(:owned, %{id: id}, scope: scope)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      {:ok, s} -> {:ok, s}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Fetches an enrollment by id, scoped to the scope's tenant (IDOR guard): an
  enrollment that belongs to a different workspace is invisible, same as
  any other cross-tenant read.
  """
  def fetch_owned_enrollment(%Scope{} = scope, id) do
    case Ash.get(Enrollment, id, scope: scope) do
      {:ok, e} -> {:ok, e}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Matricule-exact + name-fragment lookup for the school enrollment search
  box, deduplicated and capped at 10 results, each with its enrollments (class
  and year loaded) so the search shows the last class and who is already enrolled.
  """
  def search_students(%Scope{} = scope, query) do
    q = String.trim(query)

    if q == "" do
      []
    else
      by_matricule =
        Student
        |> Ash.Query.for_read(:by_matricule, %{matricule: q}, scope: scope)
        |> Ash.read!()

      by_name =
        Student
        |> Ash.Query.for_read(:search_by_name, %{query: String.downcase(q)}, scope: scope)
        |> Ash.read!()

      (by_matricule ++ by_name)
      |> Enum.uniq_by(& &1.id)
      |> Enum.take(10)
      |> Ash.load!([enrollments: [:class_group, :academic_year]], scope: scope)
    end
  end

  # --- Guardians (spec KLM1) ---------------------------------------------------

  @doc "Whether the scope edits the school register: students' identity and guardians (admin or SG)."
  def can_manage_register?(%Scope{current_user: %{} = user, current_workspace: %{id: ws_id}}),
    do:
      Checks.SchoolRole.holds?(user, ws_id, :admin) or
        Checks.SchoolRole.holds?(user, ws_id, :conduct)

  def can_manage_register?(_scope), do: false

  @doc "Per student id, the student's main contact guardian (absent when none)."
  def primary_guardians(%Scope{} = scope, student_ids) do
    StudentGuardian
    |> Ash.Query.filter(student_id in ^student_ids and primary_contact == true)
    |> Ash.Query.load(:guardian)
    |> Ash.read!(scope: scope)
    |> Map.new(&{&1.student_id, &1.guardian})
  end

  @doc """
  Spec bulletin v2 §5.2: per student id, up to two guardians as `%{name, phone}`, main
  contact first — one query for the class.
  """
  def guardians_for_students(%Scope{}, []), do: %{}

  def guardians_for_students(%Scope{} = scope, student_ids) do
    StudentGuardian
    |> Ash.Query.filter(student_id in ^student_ids)
    |> Ash.Query.sort(primary_contact: :desc, inserted_at: :asc)
    |> Ash.Query.load(:guardian)
    |> Ash.read!(scope: scope)
    |> Enum.group_by(& &1.student_id, &%{name: &1.guardian.full_name, phone: &1.guardian.phone})
    |> Map.new(fn {id, guardians} -> {id, Enum.take(guardians, 2)} end)
  end

  @doc "Whether the scope may record parents (admin or conduct axis)."
  def can_manage_guardians?(scope), do: Ash.can?({Guardian, :create}, scope)

  @doc "The student's guardian links with their guardian, main contact first."
  def list_guardian_links(%Scope{} = scope, %Student{id: id}) do
    StudentGuardian
    |> Ash.Query.for_read(:for_student, %{student_id: id}, scope: scope)
    |> Ash.read!()
  end

  @doc """
  Élèves redesign: per guardian id, the students the guardian is linked to
  (by name), each with this year's class label or nil — one query.
  """
  def guardian_children(%Scope{}, []), do: %{}

  def guardian_children(%Scope{} = scope, guardian_ids) do
    year_id = scope.current_academic_year && scope.current_academic_year.id

    StudentGuardian
    |> Ash.Query.filter(guardian_id in ^guardian_ids)
    |> Ash.Query.load(student: [enrollments: :class_group])
    |> Ash.read!(scope: scope)
    |> Enum.group_by(& &1.guardian_id, fn link ->
      enrollment = Enum.find(link.student.enrollments, &(&1.academic_year_id == year_id))
      %{student: link.student, class_label: enrollment && enrollment.class_group.label}
    end)
    |> Map.new(fn {id, children} -> {id, Enum.sort_by(children, & &1.student.full_name)} end)
  end

  @doc "The school's guardians whose phone matches `phone` once normalised; `[]` for an invalid number."
  def find_guardians_by_phone(%Scope{} = scope, phone) do
    if Guardian.Phone.valid?(phone) do
      Guardian
      |> Ash.Query.for_read(:by_phone_key, %{phone_key: Guardian.Phone.key(phone)}, scope: scope)
      |> Ash.read!()
    else
      []
    end
  end

  @doc "Creates a guardian and links it to `student` in one transaction."
  def add_guardian(%Scope{} = scope, %Student{} = student, attrs) do
    Ash.transact([Guardian, StudentGuardian], fn ->
      with {:ok, guardian} <-
             Guardian |> Ash.Changeset.for_create(:create, attrs, scope: scope) |> Ash.create(),
           {:ok, _link} <- link_guardian(scope, student, guardian) do
        guardian
      else
        {:error, error} -> Ash.DataLayer.rollback(Guardian, error)
      end
    end)
  end

  @doc "Links an existing guardian to `student`; the student's first link becomes the main contact."
  def link_guardian(%Scope{} = scope, %Student{id: student_id}, %Guardian{id: guardian_id}) do
    StudentGuardian
    |> Ash.Changeset.for_create(:link, %{student_id: student_id, guardian_id: guardian_id},
      scope: scope
    )
    |> Ash.create()
    |> case do
      {:ok, link} ->
        {:ok, link}

      {:error, error} ->
        if identity_error?(error, "unique_link"),
          do: {:error, :already_linked},
          else: {:error, error}
    end
  end

  def update_guardian(%Scope{} = scope, %Guardian{} = guardian, attrs) do
    guardian
    |> Ash.Changeset.for_update(:update, attrs, scope: scope)
    |> Ash.update()
  end

  def make_primary_guardian(%Scope{} = scope, %StudentGuardian{} = link) do
    link
    |> Ash.Changeset.for_update(:make_primary, %{}, scope: scope)
    |> Ash.update()
  end

  def unlink_guardian(%Scope{} = scope, %StudentGuardian{} = link) do
    link
    |> Ash.Changeset.for_destroy(:unlink, %{}, scope: scope)
    |> Ash.destroy()
  end

  defp identity_error?(%Ash.Error.Invalid{errors: errors}, name),
    do: Enum.any?(errors, &identity_error?(&1, name))

  defp identity_error?(%Ash.Error.Changes.InvalidAttribute{private_vars: vars}, name) do
    constraint = vars[:constraint]
    is_binary(constraint) and String.contains?(constraint, name)
  end

  defp identity_error?(_error, _name), do: false

  @doc """
  Spec KLM1 (M3): `:manage` for admins and the SG, `:read` for a form master or
  teacher of a class the student is enrolled in this year, else `:none`.
  """
  def student_access(%Scope{} = scope, %Student{} = student) do
    cond do
      can_manage_register?(scope) -> :manage
      teaches_or_masters?(scope, student) -> :read
      true -> :none
    end
  end

  defp teaches_or_masters?(
         %Scope{current_user: %{id: uid}, current_academic_year: %{id: year_id}} = scope,
         student
       ) do
    Enrollment
    |> Ash.Query.for_read(:for_student, %{student_id: student.id}, scope: scope)
    |> Ash.Query.filter(
      academic_year_id == ^year_id and
        (class_group.form_master_user_id == ^uid or
           exists(class_group.teaching_contexts, teacher_user_id == ^uid))
    )
    |> Ash.exists?()
  end

  defp teaches_or_masters?(_scope, _student), do: false

  @doc "Spec KLM1 (M3): the student's enrollments with class and year, newest year first."
  def student_history(%Scope{} = scope, %Student{id: id}) do
    Enrollment
    |> Ash.Query.for_read(:for_student, %{student_id: id}, scope: scope)
    |> Ash.read!()
    |> Enum.sort_by(& &1.academic_year.start_date, {:desc, Date})
  end

  # --- Enrollment / roster -------------------------------------------------

  def list_students(%Scope{} = scope, %ClassGroup{id: cg_id}) do
    cg_id
    |> roster_query(scope)
    |> Enum.map(& &1.student)
    |> Enum.sort_by(&String.downcase(&1.full_name))
  end

  def list_roster(%Scope{} = scope, %ClassGroup{id: cg_id}) do
    cg_id
    |> roster_query(scope)
    |> Enum.map(&%{student: &1.student, enrollment: &1})
    |> Enum.sort_by(&String.downcase(&1.student.full_name))
  end

  @doc """
  Spec KLM1 (L3): one page (50) of `year`'s enrollments, class order then name,
  with the student's main contact. `opts`: `query` (name fragment or exact
  matricule), `class_group_id`, `no_contact` (only students with no main contact),
  `offset`.
  """
  def list_school_students(%Scope{} = scope, %AcademicYear{id: year_id}, opts \\ []) do
    query =
      case opts[:query] |> to_string() |> String.trim() do
        "" -> nil
        q -> String.downcase(q)
      end

    Enrollment
    |> Ash.Query.for_read(
      :school_list,
      %{
        academic_year_id: year_id,
        class_group_id: opts[:class_group_id],
        query: query,
        no_contact: opts[:no_contact] || false
      },
      scope: scope
    )
    |> Ash.read!(page: [limit: 50, offset: opts[:offset] || 0, count: true])
  end

  @doc "Élèves redesign: the year's enrolled students, and those with no main contact."
  def student_counts(%Scope{} = scope, %AcademicYear{id: year_id}) do
    count = fn no_contact ->
      Enrollment
      |> Ash.Query.for_read(
        :school_list,
        %{academic_year_id: year_id, no_contact: no_contact},
        scope: scope
      )
      |> Ash.count!()
    end

    %{total: count.(false), no_contact: count.(true)}
  end

  @doc """
  Spec KLM5 / 2026-10-08: a class's headcount against its maximum — the class's
  own `max_size`, else the school's — a warning, never a block. `near?` marks
  90 % and more while still within the limit.
  """
  def capacity(%Scope{} = scope, %ClassGroup{} = cg),
    do: capacity(scope, cg, length(list_roster(scope, cg)))

  @doc "The capacity map for a headcount the caller already knows."
  def capacity(%Scope{} = scope, %ClassGroup{} = cg, count),
    do: capacity_of(count, cg.max_size || school_max_size(scope))

  @doc "The capacity map for a known headcount and maximum (nil when none is set)."
  def capacity_of(count, max) when is_integer(count) do
    over? = is_integer(max) and count > max
    near? = is_integer(max) and not over? and count >= ceil(max * 0.9)
    %{count: count, max: max, over?: over?, near?: near?}
  end

  @doc "The school's default maximum class size, or nil."
  def school_max_size(%Scope{} = scope) do
    case TeacherAssistant.Accounts.fetch_school_profile(scope) do
      {:ok, profile} -> profile.max_class_size
      _ -> nil
    end
  end

  defp roster_query(cg_id, %Scope{} = scope) do
    Enrollment
    |> Ash.Query.for_read(:for_class_group, %{class_group_id: cg_id}, scope: scope)
    |> Ash.read!()
  end

  @doc """
  Creates a `Student` and its first (`:inscription`) `Enrollment` atomically.
  Returns `{:ok, student}` — the `Enrollment` created alongside it is only
  reachable via `list_roster/2`.
  """
  def add_student(%Scope{} = scope, %ClassGroup{} = cg, attrs) do
    case do_enroll_new(scope, cg, attrs) do
      {:ok, %{student: student}} -> {:ok, student}
      {:error, error} -> {:error, Ash.Error.to_error_class(error)}
    end
  end

  @doc """
  Creates a `Student` and its first (`:inscription`) `Enrollment` atomically
  (school-facing path). Returns `{:ok, %{student: student, enrollment: enrollment}}`,
  or `{:error, :duplicate_matricule}` when the workspace's unique matricule
  index rejected the insert.
  """
  def enroll_new(%Scope{} = scope, %ClassGroup{} = cg, attrs) do
    case do_enroll_new(scope, cg, attrs) do
      {:ok, %{student: _, enrollment: _} = ok} ->
        {:ok, ok}

      {:error, error} ->
        case Ash.Error.to_error_class(error) do
          %Ash.Error.Forbidden{} = forbidden ->
            {:error, forbidden}

          error ->
            if duplicate_matricule?(error),
              do: {:error, :duplicate_matricule},
              else: {:error, error}
        end
    end
  end

  defp do_enroll_new(%Scope{} = scope, %ClassGroup{} = cg, attrs) do
    {repeater, attrs} = Map.pop(attrs, :repeater, false)
    {status, attrs} = Map.pop(attrs, :status, :inscription)
    {guardian, attrs} = Map.pop(attrs, :guardian)

    Enrollment
    |> Ash.ActionInput.for_action(
      :enroll_new,
      %{
        class_group_id: cg.id,
        academic_year_id: cg.academic_year_id,
        repeater: repeater,
        status: status,
        student_attrs: attrs,
        guardian: guardian
      },
      scope: scope
    )
    |> Ash.run_action()
  end

  def enroll_existing(%Scope{} = scope, %ClassGroup{} = cg, %Student{} = student, attrs \\ %{}) do
    Enrollment
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{
        student_id: student.id,
        class_group_id: cg.id,
        academic_year_id: cg.academic_year_id,
        status: :reinscription
      }),
      scope: scope
    )
    |> Ash.create()
    |> handle_enroll_existing_result()
  end

  defp handle_enroll_existing_result(result) do
    case result do
      {:ok, e} ->
        {:ok, e}

      {:error, error} ->
        if already_enrolled?(error), do: {:error, :already_enrolled}, else: {:error, error}
    end
  end

  def transfer(%Scope{} = scope, %Enrollment{} = e, %ClassGroup{} = cg) do
    if cg.academic_year_id == e.academic_year_id do
      update_enrollment(e, %{class_group_id: cg.id}, scope: scope)
    else
      {:error, :different_year}
    end
  end

  def withdraw(%Scope{} = scope, %Enrollment{} = e) do
    case Ash.destroy(e, scope: scope) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Élèves redesign: classifies each pasted row against current data without
  writing anything. Returns `[{row, action, parent}]` in input order, where
  `action` is `:create`, `{:reenroll, student, last_enrollment | nil}`,
  `{:conflict, :already_enrolled, class_label}`,
  `{:conflict, :matricule_taken, other_student_name}`,
  `{:conflict, :repeated_in_list, first_row_name}`,
  `{:conflict, :lookup_failed, nil}` or `{:error, :sex}`, and `parent` is
  `nil`, `{:invalid, phone}`, `{:existing, guardian}` or `{:new, phone}`.
  """
  def preview_rows(%Scope{} = scope, %ClassGroup{} = cg, rows) do
    rows
    |> Enum.map_reduce(%{}, fn row, seen ->
      mat = row[:matricule]

      action =
        case seen do
          # A matricule repeated in the paste: only its first line counts.
          %{^mat => first} when is_binary(mat) -> {:conflict, :repeated_in_list, first}
          _ -> classify_row(scope, cg, row)
        end

      {{row, action, classify_parent(scope, row[:guardian])},
       if(is_binary(mat), do: Map.put_new(seen, mat, row.full_name), else: seen)}
    end)
    |> elem(0)
  end

  @doc "How many students the preview would enroll (creations and re-enrolments)."
  def importable_count(preview),
    do: Enum.count(preview, fn {_row, action, _parent} -> importable?(action) end)

  @doc "Whether a preview action enrolls the student (a creation or a re-enrolment)."
  def importable?(:create), do: true
  def importable?({:reenroll, _student, _last}), do: true
  def importable?(_action), do: false

  @doc """
  Imports a roster: each row is re-classified (the preview is not trusted)
  and enrolled as a new student (`enroll_new/3`) or a re-enrolment
  (`enroll_existing/4`); errors and conflicts are skipped. A single row's
  failure never blocks the rest of the batch (each row's own student +
  enrollment write is atomic, the import as a whole is best-effort).
  Returns `%{created, reenrolled, skipped: [row + :reason], guardian_issues}`.
  """
  def import_rows(%Scope{} = scope, %ClassGroup{} = cg, rows) do
    scope
    |> preview_rows(cg, rows)
    |> Enum.reduce(
      %{created: 0, reenrolled: 0, skipped: [], guardian_issues: []},
      fn {row, action, parent}, acc ->
        case action do
          :create ->
            attrs = Map.take(row, [:full_name, :sex, :matricule, :repeater, :birth_date])

            case enroll_new(scope, cg, attrs) do
              {:ok, %{student: student}} ->
                attach_guardian(%{acc | created: acc.created + 1}, scope, student, row, parent)

              {:error, reason} ->
                skip(acc, row, reason)
            end

          {:reenroll, student, _last} ->
            case enroll_existing(scope, cg, student, %{repeater: row[:repeater] || false}) do
              {:ok, _} ->
                attach_guardian(
                  %{acc | reenrolled: acc.reenrolled + 1},
                  scope,
                  student,
                  row,
                  parent
                )

              {:error, reason} ->
                skip(acc, row, reason)
            end

          {:conflict, reason, _detail} ->
            skip(acc, row, reason)

          {:error, reason} ->
            skip(acc, row, reason)
        end
      end
    )
    |> Map.update!(:skipped, &Enum.reverse/1)
    |> Map.update!(:guardian_issues, &Enum.reverse/1)
  end

  # The row's parent, matched by phone or created, becomes a guardian. The
  # lookup runs again here: an earlier row of the same paste may have just
  # created that parent (siblings).
  defp attach_guardian(acc, _scope, _student, _row, nil), do: acc

  defp attach_guardian(acc, _scope, student, _row, {:invalid, phone}),
    do: guardian_issue(acc, student, phone, :invalid_phone)

  defp attach_guardian(
         acc,
         scope,
         student,
         %{guardian: %{full_name: name, phone: phone}},
         _parent
       ) do
    result =
      case find_guardians_by_phone(scope, phone) do
        [guardian | _] ->
          link_guardian(scope, student, guardian)

        [] ->
          add_guardian(scope, student, %{full_name: name, relationship: :autre, phone: phone})
      end

    case result do
      {:ok, _} -> acc
      {:error, :already_linked} -> acc
      {:error, reason} -> guardian_issue(acc, student, phone, reason)
    end
  end

  defp guardian_issue(acc, student, phone, reason) do
    issue = %{full_name: student.full_name, phone: phone, reason: reason}
    %{acc | guardian_issues: [issue | acc.guardian_issues]}
  end

  defp classify_parent(_scope, nil), do: nil

  defp classify_parent(scope, %{phone: phone}) do
    if Guardian.Phone.valid?(phone) do
      case find_guardians_by_phone(scope, phone) do
        [guardian | _] -> {:existing, guardian}
        [] -> {:new, phone}
      end
    else
      {:invalid, phone}
    end
  end

  defp classify_row(_scope, _cg, %{sex: nil}), do: {:error, :sex}
  defp classify_row(_scope, _cg, %{matricule: nil}), do: :create
  defp classify_row(_scope, _cg, %{matricule: ""}), do: :create

  defp classify_row(%Scope{} = scope, cg, %{matricule: mat} = row) do
    Student
    |> Ash.Query.for_read(:by_matricule, %{matricule: mat}, scope: scope)
    |> Ash.Query.load(enrollments: [:class_group, :academic_year])
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> :create
      {:ok, student} -> classify_known(student, cg, row)
      _ -> {:conflict, :lookup_failed, nil}
    end
  end

  defp classify_known(student, cg, row) do
    this_year = Enum.find(student.enrollments, &(&1.academic_year_id == cg.academic_year_id))

    cond do
      not same_name?(student.full_name, row.full_name) ->
        {:conflict, :matricule_taken, student.full_name}

      this_year ->
        {:conflict, :already_enrolled, this_year.class_group.label}

      true ->
        last =
          Enum.max_by(student.enrollments, & &1.academic_year.start_date, Date, fn -> nil end)

        {:reenroll, student, last}
    end
  end

  # Case-, accent- and word-order-insensitive.
  defp same_name?(a, b), do: name_words(a) == name_words(b)

  defp name_words(name) do
    name
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.split()
    |> Enum.sort()
  end

  defp skip(acc, row, %Ash.Error.Forbidden{}), do: skip(acc, row, :forbidden)
  defp skip(acc, row, reason), do: %{acc | skipped: [Map.put(row, :reason, reason) | acc.skipped]}

  defp duplicate_matricule?(error) do
    error |> Exception.message() |> String.contains?("matricule")
  rescue
    _ -> false
  end

  defp already_enrolled?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &already_enrolled?/1)
  end

  defp already_enrolled?(%Ash.Error.Changes.InvalidAttribute{private_vars: private_vars}) do
    constraint = private_vars[:constraint]
    is_binary(constraint) and String.contains?(constraint, "unique_enrollment_per_year")
  end

  defp already_enrolled?(_error), do: false
end
