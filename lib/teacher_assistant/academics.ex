defmodule TeacherAssistant.Academics do
  use Ash.Domain,
    otp_app: :teacher_assistant

  require Ash.Query

  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.AcademicYear
  alias TeacherAssistant.Academics.AttendanceRecord
  alias TeacherAssistant.Academics.AttendanceSession
  alias TeacherAssistant.Academics.Learner
  alias TeacherAssistant.Academics.LessonPlanEntry
  alias TeacherAssistant.Academics.PersonalClassroom
  alias TeacherAssistant.Academics.PersonalWorkspace
  alias TeacherAssistant.Academics.TeachingLogEntry

  resources do
    resource PersonalWorkspace
    resource AcademicYear
    resource PersonalClassroom
    resource Learner
    resource AttendanceSession
    resource AttendanceRecord
    resource LessonPlanEntry
    resource TeachingLogEntry
  end

  def ensure_personal_workspace!(%User{} = user) do
    case personal_workspace_for_user(user) do
      {:ok, workspace} ->
        workspace

      {:error, :not_found} ->
        {:ok, workspace} =
          PersonalWorkspace
          |> Ash.Changeset.for_create(:create, %{
            name: "Personal workspace",
            owner_user_id: user.id
          })
          |> Ash.create(authorize?: false)

        workspace
    end
  end

  def personal_workspace_for_user(%User{id: user_id}) do
    PersonalWorkspace
    |> Ash.Query.filter(owner_user_id == ^user_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def get_personal_workspace(id), do: Ash.get(PersonalWorkspace, id, authorize?: false)

  def create_academic_year(%PersonalWorkspace{} = workspace, attrs) do
    attrs =
      attrs
      |> normalize_date(:start_date)
      |> normalize_date(:end_date)
      |> Map.put(:personal_workspace_id, workspace.id)
      |> Map.put_new(:active, true)

    result =
      AcademicYear
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create(authorize?: false)

    with {:ok, year} <- result do
      if year.active do
        deactivate_other_years(workspace, year.id)
      end

      {:ok, year}
    end
  end

  def list_academic_years(%PersonalWorkspace{id: workspace_id}) do
    AcademicYear
    |> Ash.Query.filter(personal_workspace_id == ^workspace_id)
    |> Ash.Query.sort(start_date: :desc)
    |> Ash.read!(authorize?: false)
  end

  def current_academic_year(%PersonalWorkspace{id: workspace_id}) do
    AcademicYear
    |> Ash.Query.filter(personal_workspace_id == ^workspace_id and active == true)
    |> Ash.Query.sort(start_date: :desc)
    |> Ash.read_one!(authorize?: false)
  end

  def create_personal_classroom(%PersonalWorkspace{} = workspace, %AcademicYear{} = year, attrs) do
    attrs =
      attrs
      |> trim_fields([:class_label, :subject])
      |> Map.put(:personal_workspace_id, workspace.id)
      |> Map.put(:academic_year_id, year.id)

    PersonalClassroom
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false)
  end

  def list_personal_classrooms(%PersonalWorkspace{id: workspace_id}) do
    PersonalClassroom
    |> Ash.Query.filter(personal_workspace_id == ^workspace_id)
    |> Ash.Query.sort(class_label: :asc, subject: :asc)
    |> Ash.read!(authorize?: false)
  end

  def get_personal_classroom(id), do: Ash.get(PersonalClassroom, id, authorize?: false)

  def create_learner(%PersonalClassroom{} = classroom, attrs) do
    attrs =
      attrs
      |> trim_fields([:first_name, :last_name, :identifier])
      |> Map.put(:personal_classroom_id, classroom.id)

    Learner
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false)
    |> load_result(:full_name)
  end

  def list_learners(%PersonalClassroom{id: classroom_id}) do
    Learner
    |> Ash.Query.filter(personal_classroom_id == ^classroom_id)
    |> Ash.Query.sort(last_name: :asc, first_name: :asc)
    |> Ash.Query.load(:full_name)
    |> Ash.read!(authorize?: false)
  end

  def create_attendance_session(%PersonalClassroom{} = classroom, attrs) do
    attrs =
      attrs
      |> normalize_date(:date)
      |> trim_fields([:notes])
      |> Map.put(:personal_classroom_id, classroom.id)

    AttendanceSession
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false)
  end

  def list_recent_attendance_sessions(%PersonalWorkspace{id: workspace_id}, limit \\ 5) do
    AttendanceSession
    |> Ash.Query.filter(personal_classroom.personal_workspace_id == ^workspace_id)
    |> Ash.Query.sort(date: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load(:personal_classroom)
    |> Ash.read!(authorize?: false)
  end

  def record_attendance(%AttendanceSession{} = session, %Learner{} = learner, attrs) do
    attrs =
      attrs
      |> trim_fields([:note])
      |> Map.put(:attendance_session_id, session.id)
      |> Map.put(:learner_id, learner.id)

    AttendanceRecord
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false)
  end

  def list_attendance_records(%AttendanceSession{id: session_id}) do
    AttendanceRecord
    |> Ash.Query.filter(attendance_session_id == ^session_id)
    |> Ash.Query.load(:learner)
    |> Ash.read!(authorize?: false)
  end

  def create_lesson_plan_entry(%PersonalClassroom{} = classroom, attrs) do
    attrs =
      attrs
      |> normalize_date(:planned_on)
      |> normalize_decimal(:planned_hours)
      |> trim_fields([:title, :objectives])
      |> Map.put(:personal_classroom_id, classroom.id)

    LessonPlanEntry
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false)
  end

  def list_lesson_plan_entries(%PersonalWorkspace{id: workspace_id}) do
    LessonPlanEntry
    |> Ash.Query.filter(personal_classroom.personal_workspace_id == ^workspace_id)
    |> Ash.Query.sort(planned_on: :desc)
    |> Ash.Query.load([:personal_classroom, :teaching_logs])
    |> Ash.read!(authorize?: false)
  end

  def create_teaching_log_entry(%LessonPlanEntry{} = plan, attrs) do
    attrs =
      attrs
      |> normalize_date(:taught_on)
      |> normalize_decimal(:taught_hours)
      |> trim_fields([:notes])
      |> Map.put(:lesson_plan_entry_id, plan.id)

    TeachingLogEntry
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false)
  end

  def dashboard_metrics(%PersonalWorkspace{} = workspace) do
    %{
      academic_year: current_academic_year(workspace),
      classrooms_count: length(list_personal_classrooms(workspace)),
      recent_attendance: list_recent_attendance_sessions(workspace),
      lesson_entries: list_lesson_plan_entries(workspace)
    }
  end

  defp deactivate_other_years(workspace, active_year_id) do
    workspace
    |> list_academic_years()
    |> Enum.reject(&(&1.id == active_year_id))
    |> Enum.each(fn year ->
      year
      |> Ash.Changeset.for_update(:update, %{active: false})
      |> Ash.update!(authorize?: false)
    end)
  end

  defp normalize_date(attrs, key) do
    Map.update(attrs, key, nil, fn
      "" -> nil
      %Date{} = date -> date
      value when is_binary(value) -> Date.from_iso8601!(value)
      value -> value
    end)
  end

  defp normalize_decimal(attrs, key) do
    Map.update(attrs, key, nil, fn
      "" -> nil
      %Decimal{} = decimal -> decimal
      value when is_binary(value) -> Decimal.new(value)
      value when is_integer(value) -> Decimal.new(value)
      value -> value
    end)
  end

  defp trim_fields(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc ->
      Map.update(acc, field, nil, fn
        value when is_binary(value) -> String.trim(value)
        value -> value
      end)
    end)
  end

  defp load_result({:ok, record}, load), do: {:ok, Ash.load!(record, load, authorize?: false)}
  defp load_result(result, _load), do: result
end
