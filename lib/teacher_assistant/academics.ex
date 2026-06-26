defmodule TeacherAssistant.Academics do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.PersonalWorkspace
  alias TeacherAssistant.Academics.AcademicYear

  resources do
    resource PersonalWorkspace
    resource AcademicYear
  end

  def ensure_personal_workspace!(%User{} = user) do
    case personal_workspace_for_user(user) do
      {:ok, ws} -> ws
      {:error, :not_found} ->
        {:ok, ws} =
          PersonalWorkspace
          |> Ash.Changeset.for_create(:create, %{name: "Personal workspace", owner_user_id: user.id})
          |> Ash.create(authorize?: false)
        ws
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

  def create_academic_year(%PersonalWorkspace{} = ws, attrs) do
    attrs = attrs |> Map.put(:personal_workspace_id, ws.id) |> Map.put_new(:active, true)

    with {:ok, year} <- AcademicYear |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false) do
      if year.active, do: deactivate_other_years(ws, year.id)
      {:ok, year}
    end
  end

  def list_academic_years(%PersonalWorkspace{id: id}) do
    AcademicYear
    |> Ash.Query.filter(personal_workspace_id == ^id)
    |> Ash.Query.sort(start_date: :desc)
    |> Ash.read!(authorize?: false)
  end

  def current_academic_year(%PersonalWorkspace{id: id}) do
    AcademicYear
    |> Ash.Query.filter(personal_workspace_id == ^id and active == true)
    |> Ash.Query.sort(start_date: :desc)
    |> Ash.read!(authorize?: false)
    |> List.first()
  end

  def get_academic_year(id), do: Ash.get(AcademicYear, id, authorize?: false)

  defp deactivate_other_years(%PersonalWorkspace{id: ws_id}, keep_id) do
    AcademicYear
    |> Ash.Query.filter(personal_workspace_id == ^ws_id and id != ^keep_id and active == true)
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn y -> y |> Ash.Changeset.for_update(:update, %{active: false}) |> Ash.update!(authorize?: false) end)
  end
end
