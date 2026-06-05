defmodule TeacherAssistant.Academics.PersonalWorkspace do
  @moduledoc """
  Teacher-owned setup helpers for personal workspaces.

  These functions intentionally use `authorize?: false` after verifying the
  selected workspace is the current teacher's personal workspace. That keeps
  school configuration policies unchanged while allowing private setup data.
  """

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.AcademicYear
  alias TeacherAssistant.Academics.Classroom
  alias TeacherAssistant.Academics.ClassroomStudent
  alias TeacherAssistant.Academics.Level
  alias TeacherAssistant.Academics.LevelOption
  alias TeacherAssistant.Academics.LevelOptionSubject
  alias TeacherAssistant.Academics.Option
  alias TeacherAssistant.Academics.ProgressionEntry
  alias TeacherAssistant.Academics.ProgressionPlan
  alias TeacherAssistant.Academics.Student
  alias TeacherAssistant.Academics.Subject
  alias TeacherAssistant.Academics.TeachingAssignment
  alias TeacherAssistant.Scope

  def create_setup(%Scope{} = scope, params) when is_map(params) do
    with :ok <- ensure_personal_scope(scope),
         {:ok, attrs} <- setup_attrs(params),
         :ok <- ensure_academic_year_name_available(scope, attrs.academic_year_name),
         {:ok, academic_year} <- create_academic_year(scope, attrs) do
      option = create_option!(scope, attrs.option_name)
      level = create_level!(scope, attrs.class_name)
      level_option = create_level_option!(scope, level.id, option.id)
      classroom = create_classroom!(scope, academic_year.id, level_option.id)
      subject = create_subject!(scope, attrs.subject_name, attrs.coefficient)

      level_option_subject =
        create_level_option_subject!(scope, level_option.id, subject.id, attrs.coefficient)

      teaching_assignment =
        create_teaching_assignment!(
          scope,
          classroom.id,
          level_option_subject.id,
          scope.current_user.id
        )

      students =
        attrs.students
        |> Enum.map(&create_student_and_enrollment!(scope, classroom.id, &1))
        |> Enum.map(& &1.student)

      {:ok,
       %{
         academic_year: academic_year,
         level: level,
         option: option,
         level_option: level_option,
         classroom: classroom,
         subject: subject,
         level_option_subject: level_option_subject,
         teaching_assignment: teaching_assignment,
         students: students
       }}
    end
  end

  def import_students(%Scope{} = scope, classroom_id, csv) when is_binary(csv) do
    with :ok <- ensure_personal_scope(scope),
         {:ok, classroom} <- get_personal_classroom(scope, classroom_id),
         {:ok, rows} <- parse_csv(csv) do
      {valid, invalid} =
        rows
        |> Enum.map(&validate_student_row/1)
        |> Enum.split_with(fn
          {:ok, _row} -> true
          {:error, _row} -> false
        end)

      created =
        valid
        |> Enum.map(fn {:ok, row} ->
          create_student_and_enrollment!(scope, classroom.id, row).student
        end)

      {:ok,
       %{
         created: created,
         invalid: Enum.map(invalid, fn {:error, row} -> row end)
       }}
    end
  end

  def create_student(%Scope{} = scope, classroom_id, params) when is_map(params) do
    with :ok <- ensure_personal_scope(scope),
         {:ok, classroom} <- get_personal_classroom(scope, classroom_id),
         {:ok, attrs} <- validate_student_row(Map.put(params, :row, nil)) do
      {:ok, create_student_and_enrollment!(scope, classroom.id, attrs).student}
    end
  end

  def delete_student(%Scope{} = scope, student_id) do
    with :ok <- ensure_personal_scope(scope),
         {:ok, student} <- Ash.get(Student, student_id, scope: scope) do
      Ash.destroy(student, scope: scope, authorize?: false)
    end
  end

  def create_progression_plan(%Scope{} = scope, params) when is_map(params) do
    with :ok <- ensure_personal_scope(scope),
         {:ok, attrs} <- progression_plan_attrs(scope, params) do
      ProgressionPlan
      |> Ash.Changeset.for_create(:create, attrs, scope: scope)
      |> Ash.create(authorize?: false)
    end
  end

  def create_progression_entry(%Scope{} = scope, plan_id, params) when is_map(params) do
    with :ok <- ensure_personal_scope(scope),
         {:ok, plan} <- get_personal_progression_plan(scope, plan_id),
         {:ok, attrs} <- progression_entry_attrs(params) do
      ProgressionEntry
      |> Ash.Changeset.for_create(:create, Map.put(attrs, :progression_plan_id, plan.id),
        scope: scope
      )
      |> Ash.create(authorize?: false)
    end
  end

  def setup_ready?(%Scope{} = scope) do
    case ensure_personal_scope(scope) do
      :ok ->
        has_year? = Academics.AcademicYear |> Ash.read!(scope: scope) |> Enum.any?()

        has_assignment? =
          TeachingAssignment
          |> Ash.Query.filter(teacher_id == ^scope.current_user.id)
          |> Ash.read!(scope: scope)
          |> Enum.any?()

        has_year? && has_assignment?

      _ ->
        false
    end
  end

  defp ensure_personal_scope(%Scope{
         current_workspace_type: :personal_teacher,
         current_workspace: %{owner_user_id: owner_user_id},
         current_user: %{id: user_id, role: role}
       })
       when owner_user_id == user_id and role in [:teacher, :principal_teacher] do
    :ok
  end

  defp ensure_personal_scope(_scope), do: {:error, :personal_workspace_required}

  defp setup_attrs(params) do
    with {:ok, start_date} <- parse_date(field(params, "start_date")),
         {:ok, end_date} <- parse_date(field(params, "end_date")),
         :ok <- validate_date_order(start_date, end_date),
         {:ok, coefficient} <- parse_positive_integer(field(params, "coefficient", "1")) do
      {:ok,
       %{
         academic_year_name: required_text(params, "academic_year_name", "Academic year"),
         start_date: start_date,
         end_date: end_date,
         class_name: required_text(params, "class_name", "Class"),
         option_name: required_text(params, "option_name", "General"),
         subject_name: required_text(params, "subject_name", "Subject"),
         coefficient: coefficient,
         students: normalize_student_rows(Map.get(params, "students", []))
       }}
    end
  rescue
    ArgumentError -> {:error, :invalid_setup}
  end

  defp ensure_academic_year_name_available(scope, name) do
    AcademicYear
    |> Ash.Query.filter(name == ^name)
    |> Ash.exists?(scope: scope)
    |> case do
      true -> {:error, :academic_year_already_exists}
      false -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp create_academic_year(scope, attrs) do
    terms =
      1..3
      |> Enum.map(fn position ->
        %{
          name: "Term #{position}",
          start_date: attrs.start_date,
          end_date: attrs.end_date,
          sequences:
            1..2
            |> Enum.map(fn sequence_position ->
              %{
                name: "Sequence #{(position - 1) * 2 + sequence_position}",
                start_date: attrs.start_date,
                end_date: attrs.end_date
              }
            end)
        }
      end)

    AcademicYear
    |> Ash.Changeset.for_create(
      :create,
      %{
        name: attrs.academic_year_name,
        start_date: attrs.start_date,
        end_date: attrs.end_date,
        active: true,
        terms: terms
      },
      scope: scope
    )
    |> Ash.create(authorize?: false)
  end

  defp create_option!(scope, name) do
    Option
    |> Ash.Changeset.for_create(:create, %{name: name}, scope: scope)
    |> Ash.create!(authorize?: false)
  end

  defp create_level!(scope, name) do
    Level
    |> Ash.Changeset.for_create(:create, %{name: name}, scope: scope)
    |> Ash.create!(authorize?: false)
  end

  defp create_level_option!(scope, level_id, option_id) do
    LevelOption
    |> Ash.Changeset.for_create(:create, %{level_id: level_id, option_id: option_id},
      scope: scope
    )
    |> Ash.create!(authorize?: false)
  end

  defp create_classroom!(scope, academic_year_id, level_option_id) do
    Classroom
    |> Ash.Changeset.for_create(
      :create,
      %{academic_year_id: academic_year_id, level_option_id: level_option_id},
      scope: scope
    )
    |> Ash.create!(authorize?: false)
  end

  defp create_subject!(scope, name, coefficient) do
    Subject
    |> Ash.Changeset.for_create(
      :create,
      %{name: name, default_coefficient: coefficient},
      scope: scope
    )
    |> Ash.create!(authorize?: false)
  end

  defp create_level_option_subject!(scope, level_option_id, subject_id, coefficient) do
    LevelOptionSubject
    |> Ash.Changeset.for_create(
      :create,
      %{level_option_id: level_option_id, subject_id: subject_id, coefficient: coefficient},
      scope: scope
    )
    |> Ash.create!(authorize?: false)
  end

  defp create_teaching_assignment!(scope, classroom_id, level_option_subject_id, teacher_id) do
    TeachingAssignment
    |> Ash.Changeset.for_create(
      :create,
      %{
        classroom_id: classroom_id,
        level_option_subject_id: level_option_subject_id,
        teacher_id: teacher_id
      },
      scope: scope
    )
    |> Ash.create!(authorize?: false)
  end

  defp create_student_and_enrollment!(scope, classroom_id, row) do
    student =
      Student
      |> Ash.Changeset.for_create(:create, row, scope: scope)
      |> Ash.create!(authorize?: false)

    enrollment =
      ClassroomStudent
      |> Ash.Changeset.for_create(
        :create,
        %{classroom_id: classroom_id, student_id: student.id},
        scope: scope
      )
      |> Ash.create!(authorize?: false)

    %{student: student, enrollment: enrollment}
  end

  defp get_personal_classroom(scope, classroom_id) do
    Classroom
    |> Ash.Query.filter(id == ^classroom_id)
    |> Ash.read_one(scope: scope)
  end

  defp get_personal_progression_plan(scope, plan_id) do
    ProgressionPlan
    |> Ash.Query.filter(id == ^plan_id and teacher_id == ^scope.current_user.id)
    |> Ash.read_one(scope: scope)
  end

  defp progression_plan_attrs(scope, params) do
    {:ok,
     %{
       academic_year_id: field(params, "academic_year_id"),
       classroom_id: field(params, "classroom_id"),
       level_option_subject_id: field(params, "level_option_subject_id"),
       teacher_id: scope.current_user.id,
       weekly_hours: decimal(field(params, "weekly_hours", "0")),
       annual_hours: decimal(field(params, "annual_hours", "0")),
       status: :active
     }}
  end

  defp progression_entry_attrs(params) do
    with {:ok, week_number} <- parse_positive_integer(field(params, "week_number", "1")) do
      {:ok,
       %{
         term_id: optional_text(params, "term_id"),
         sequence_id: optional_text(params, "sequence_id"),
         week_number: week_number,
         start_date: optional_date(params, "start_date"),
         end_date: optional_date(params, "end_date"),
         title: required_text(params, "title", "Lesson"),
         planned_content: optional_text(params, "planned_content"),
         planned_hours: decimal(field(params, "planned_hours", "0")),
         entry_type: parse_entry_type(field(params, "entry_type", "lesson"))
       }}
    end
  end

  defp parse_csv(csv) do
    rows =
      csv
      |> String.trim()
      |> String.split(["\r\n", "\n"], trim: true)
      |> Enum.map(&parse_csv_line/1)

    case rows do
      [] ->
        {:ok, []}

      [headers | values] ->
        headers = Enum.map(headers, &normalize_header/1)

        rows =
          values
          |> Enum.with_index(2)
          |> Enum.map(fn {row, index} ->
            headers
            |> Enum.zip(row)
            |> Map.new()
            |> Map.put(:row, index)
          end)

        {:ok, rows}
    end
  end

  defp parse_csv_line(line) do
    line
    |> String.split(",")
    |> Enum.map(&String.trim(&1, ~s(" \t)))
  end

  defp normalize_header(header), do: header |> String.trim() |> String.downcase()

  defp validate_student_row(row) do
    attrs = normalize_student_row(row)

    errors =
      []
      |> require_row_field(attrs, :first_name)
      |> require_row_field(attrs, :last_name)

    if errors == [] do
      {:ok, attrs}
    else
      {:error, %{row: row[:row], errors: Enum.reverse(errors)}}
    end
  end

  defp require_row_field(errors, attrs, field) do
    if blank?(Map.get(attrs, field)), do: ["#{field} is required" | errors], else: errors
  end

  defp normalize_student_rows(rows) when is_list(rows) do
    rows
    |> Enum.map(&normalize_student_row/1)
    |> Enum.reject(&(blank?(&1.first_name) or blank?(&1.last_name)))
  end

  defp normalize_student_rows(_rows), do: []

  defp normalize_student_row(row) do
    %{
      first_name: optional_text(row, "first_name") || "",
      last_name: optional_text(row, "last_name") || "",
      matricule: optional_text(row, "matricule"),
      gender: parse_gender(field(row, "gender", "male")),
      date_of_birth: optional_date(row, "date_of_birth"),
      place_of_birth: optional_text(row, "place_of_birth")
    }
  end

  defp parse_gender("female"), do: :female
  defp parse_gender("F"), do: :female
  defp parse_gender("f"), do: :female
  defp parse_gender(_value), do: :male

  defp parse_entry_type(value) do
    case to_string(value) do
      "integration" -> :integration
      "evaluation" -> :evaluation
      "correction" -> :correction
      "remediation" -> :remediation
      "holiday" -> :holiday
      _ -> :lesson
    end
  end

  defp required_text(map, key, fallback) do
    value = field(map, key, fallback) |> to_string() |> String.trim()
    if value == "", do: raise(ArgumentError), else: value
  end

  defp optional_text(map, key) do
    case field(map, key, nil) do
      nil -> nil
      "" -> nil
      value -> String.trim(to_string(value))
    end
  end

  defp field(map, key, default \\ nil) do
    Map.get(map, key) || Map.get(map, String.to_atom(key), default)
  end

  defp parse_date(value) do
    case Date.from_iso8601(to_string(value || "")) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_date}
    end
  end

  defp optional_date(map, key) do
    case field(map, key, nil) do
      nil -> nil
      "" -> nil
      value -> Date.from_iso8601!(to_string(value))
    end
  end

  defp validate_date_order(start_date, end_date) do
    if Date.compare(end_date, start_date) == :gt, do: :ok, else: {:error, :date_order}
  end

  defp parse_positive_integer(nil), do: {:ok, 1}

  defp parse_positive_integer(value) do
    case Integer.parse(to_string(value)) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _ -> {:error, :invalid_integer}
    end
  end

  defp decimal(value), do: Decimal.new(to_string(value || "0"))

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""
end
