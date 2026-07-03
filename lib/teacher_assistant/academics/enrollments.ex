defmodule TeacherAssistant.Academics.Enrollments do
  @moduledoc """
  School-facing enrollment operations (P2.2). Personal-roster paths keep using
  Academics.add_student/list_roster; this module adds search, re-enrollment,
  transfer and bulk import with matricule matching.
  """
  require Ash.Query
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.{ClassGroup, Enrollment, Student, Workspace}

  def enroll_new(%ClassGroup{} = cg, attrs) do
    {repeater, attrs} = Map.pop(attrs, :repeater, false)
    {status, attrs} = Map.pop(attrs, :status, :inscription)
    attrs = Map.put(attrs, :workspace_id, cg.workspace_id)

    with {:ok, student} <-
           Student |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false),
         {:ok, enrollment} <-
           Enrollment
           |> Ash.Changeset.for_create(:create, %{
             student_id: student.id,
             class_group_id: cg.id,
             academic_year_id: cg.academic_year_id,
             workspace_id: cg.workspace_id,
             repeater: repeater,
             status: status
           })
           |> Ash.create(authorize?: false) do
      {:ok, %{student: student, enrollment: enrollment}}
    else
      {:error, error} ->
        if duplicate_matricule?(error), do: {:error, :duplicate_matricule}, else: {:error, error}
    end
  end

  def enroll_existing(%ClassGroup{} = cg, %Student{} = student, attrs \\ %{}) do
    Enrollment
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{
        student_id: student.id,
        class_group_id: cg.id,
        academic_year_id: cg.academic_year_id,
        workspace_id: cg.workspace_id,
        status: :reinscription
      })
    )
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, e} -> {:ok, e}
      {:error, _} -> {:error, :already_enrolled}
    end
  end

  def search_students(%Workspace{id: ws_id}, query) do
    q = String.trim(query)

    if q == "" do
      []
    else
      by_matricule =
        Student
        |> Ash.Query.filter(workspace_id == ^ws_id and matricule == ^q)
        |> Ash.read!(authorize?: false)

      by_name =
        Student
        |> Ash.Query.filter(
          workspace_id == ^ws_id and
            contains(string_downcase(full_name), ^String.downcase(q))
        )
        |> Ash.Query.sort(full_name: :asc)
        |> Ash.Query.limit(10)
        |> Ash.read!(authorize?: false)

      Enum.uniq_by(by_matricule ++ by_name, & &1.id) |> Enum.take(10)
    end
  end

  def transfer(%Enrollment{} = e, %ClassGroup{} = cg) do
    if cg.academic_year_id == e.academic_year_id do
      Academics.update_enrollment(e, %{class_group_id: cg.id})
    else
      {:error, :different_year}
    end
  end

  def withdraw(%Enrollment{} = e) do
    Ash.destroy!(e, authorize?: false)
    :ok
  end

  def import_rows(%ClassGroup{} = cg, rows) do
    ws = %Workspace{id: cg.workspace_id}

    Enum.reduce(rows, %{created: 0, reenrolled: 0, conflicts: []}, fn row, acc ->
      case classify_row(ws, cg, row) do
        :create ->
          case enroll_new(cg, Map.take(row, [:full_name, :sex, :matricule, :repeater])) do
            {:ok, _} -> %{acc | created: acc.created + 1}
            {:error, reason} -> conflict(acc, row, reason)
          end

        {:reenroll, student} ->
          case enroll_existing(cg, student, %{repeater: row[:repeater] || false}) do
            {:ok, _} -> %{acc | reenrolled: acc.reenrolled + 1}
            {:error, reason} -> conflict(acc, row, reason)
          end

        {:conflict, reason} ->
          conflict(acc, row, reason)
      end
    end)
  end

  defp classify_row(_ws, _cg, %{matricule: nil}), do: :create
  defp classify_row(_ws, _cg, %{matricule: ""}), do: :create

  defp classify_row(ws, cg, %{matricule: mat}) do
    case Student
         |> Ash.Query.filter(workspace_id == ^ws.id and matricule == ^mat)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        :create

      {:ok, student} ->
        if enrolled_this_year?(student, cg),
          do: {:conflict, :already_enrolled},
          else: {:reenroll, student}

      _ ->
        {:conflict, :lookup_failed}
    end
  end

  defp enrolled_this_year?(student, cg) do
    Enrollment
    |> Ash.Query.filter(student_id == ^student.id and academic_year_id == ^cg.academic_year_id)
    |> Ash.read!(authorize?: false) != []
  end

  defp conflict(acc, row, reason),
    do: %{acc | conflicts: acc.conflicts ++ [Map.put(row, :reason, reason)]}

  defp duplicate_matricule?(error) do
    error |> Exception.message() |> String.contains?("matricule")
  rescue
    _ -> false
  end
end
