defmodule TeacherAssistant.Enrollment do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

  alias TeacherAssistant.Academics.{AcademicYear, ClassGroup, Enrollment, Student, Workspace}
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Scope

  resources do
    resource ClassGroup do
      define :update_class_group, action: :update
    end

    resource Student do
      define :update_student, action: :update
    end

    resource Enrollment do
      define :update_enrollment, action: :update
    end
  end

  authorization do
    authorize :when_requested
  end

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

  def list_class_groups(%Scope{} = scope, %AcademicYear{id: year_id}) do
    ClassGroup
    |> Ash.Query.for_read(:for_workspace_and_year, %{academic_year_id: year_id}, scope: scope)
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
      Ash.destroy!(cg, scope: scope)
      :ok
    end
  end

  @doc """
  Sets (or clears, with `user_id: nil`) `cg`'s form master. A non-`nil`
  `user_id` must name an active `SchoolMembership` in `cg`'s own workspace —
  `User` isn't multitenant, so this is the tenant check for it (mirrors
  `Curriculum.assign_teacher/4`'s `assignable_ws/2`).
  """
  def set_form_master(%Scope{} = scope, %ClassGroup{} = cg, nil) do
    cg
    |> Ash.Changeset.for_update(:update, %{form_master_user_id: nil}, scope: scope)
    |> Ash.update()
  end

  def set_form_master(%Scope{} = scope, %ClassGroup{} = cg, user_id) do
    with {:ok, _membership} <-
           Accounts.fetch_school_membership(%Workspace{id: cg.workspace_id}, %User{id: user_id}) do
      cg
      |> Ash.Changeset.for_update(:update, %{form_master_user_id: user_id}, scope: scope)
      |> Ash.update()
    end
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
  box, deduplicated and capped at 10 results.
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

      Enum.uniq_by(by_matricule ++ by_name, & &1.id) |> Enum.take(10)
    end
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
        error = Ash.Error.to_error_class(error)

        if duplicate_matricule?(error), do: {:error, :duplicate_matricule}, else: {:error, error}
    end
  end

  defp do_enroll_new(%Scope{} = scope, %ClassGroup{} = cg, attrs) do
    {repeater, attrs} = Map.pop(attrs, :repeater, false)
    {status, attrs} = Map.pop(attrs, :status, :inscription)

    Enrollment
    |> Ash.ActionInput.for_action(
      :enroll_new,
      %{
        class_group_id: cg.id,
        academic_year_id: cg.academic_year_id,
        repeater: repeater,
        status: status,
        student_attrs: attrs
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
  Classifies each row against current data without writing anything.
  Returns `[{row, :create | :reenroll | {:conflict, reason}}]` in input order.
  """
  def preview_rows(%Scope{} = scope, %ClassGroup{} = cg, rows) do
    Enum.map(rows, fn row -> {row, classify_row(scope, cg, row)} end)
  end

  @doc """
  Imports a roster: each row is independently classified as a new student
  (`enroll_new/3`), a re-enrollment (`enroll_existing/4`), or a conflict —
  a single row's failure never blocks the rest of the batch (each row's own
  student+enrollment write is atomic via `enroll_new/3`'s `:enroll_new`
  action, but the import as a whole is deliberately best-effort/partial,
  matching the pre-existing behavior).
  """
  def import_rows(%Scope{} = scope, %ClassGroup{} = cg, rows) do
    scope
    |> preview_rows(cg, rows)
    |> Enum.reduce(%{created: 0, reenrolled: 0, conflicts: []}, fn {row, action}, acc ->
      case action do
        :create ->
          case enroll_new(scope, cg, Map.take(row, [:full_name, :sex, :matricule, :repeater])) do
            {:ok, _} -> %{acc | created: acc.created + 1}
            {:error, reason} -> conflict(acc, row, reason)
          end

        {:reenroll, student} ->
          case enroll_existing(scope, cg, student, %{repeater: row[:repeater] || false}) do
            {:ok, _} -> %{acc | reenrolled: acc.reenrolled + 1}
            {:error, reason} -> conflict(acc, row, reason)
          end

        {:conflict, reason} ->
          conflict(acc, row, reason)
      end
    end)
  end

  defp classify_row(_scope, _cg, %{matricule: nil}), do: :create
  defp classify_row(_scope, _cg, %{matricule: ""}), do: :create

  defp classify_row(%Scope{} = scope, cg, %{matricule: mat}) do
    case Student
         |> Ash.Query.for_read(:by_matricule, %{matricule: mat}, scope: scope)
         |> Ash.read_one() do
      {:ok, nil} ->
        :create

      {:ok, student} ->
        if enrolled_this_year?(scope, student, cg),
          do: {:conflict, :already_enrolled},
          else: {:reenroll, student}

      _ ->
        {:conflict, :lookup_failed}
    end
  end

  defp enrolled_this_year?(%Scope{} = scope, student, cg) do
    Enrollment
    |> Ash.Query.for_read(
      :for_student_and_year,
      %{
        student_id: student.id,
        academic_year_id: cg.academic_year_id
      },
      scope: scope
    )
    |> Ash.read!() != []
  end

  defp conflict(acc, row, reason),
    do: %{acc | conflicts: acc.conflicts ++ [Map.put(row, :reason, reason)]}

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
