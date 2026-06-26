defmodule TeacherAssistant.Academics do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query
  alias TeacherAssistant.Accounts.User
  alias TeacherAssistant.Academics.PersonalWorkspace
  alias TeacherAssistant.Academics.AcademicYear
  alias TeacherAssistant.Academics.Term
  alias TeacherAssistant.Academics.Sequence
  alias TeacherAssistant.Academics.TeachingContext
  alias TeacherAssistant.Academics.ProgressionPlan

  resources do
    resource PersonalWorkspace
    resource AcademicYear
    resource Term
    resource Sequence
    resource TeachingContext
    resource ProgressionPlan
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

  def build_default_calendar(%AcademicYear{} = year) do
    preset = TeacherAssistant.Academics.Reference.default_calendar_preset()

    Enum.each(preset.terms, fn term_spec ->
      {:ok, term} =
        Term
        |> Ash.Changeset.for_create(:create, %{position: term_spec.position, academic_year_id: year.id})
        |> Ash.create(authorize?: false)

      Enum.each(term_spec.sequences, fn s ->
        Sequence
        |> Ash.Changeset.for_create(:create, Map.put(Map.take(s, [:number, :position_in_term, :start_date, :end_date, :integration_week]), :term_id, term.id))
        |> Ash.create!(authorize?: false)
      end)
    end)

    :ok
  end

  def list_sequences(%AcademicYear{id: year_id}) do
    Sequence
    |> Ash.Query.filter(term.academic_year_id == ^year_id)
    |> Ash.Query.load(:term)
    |> Ash.Query.sort(number: :asc)
    |> Ash.read!(authorize?: false)
  end

  def current_sequence(%AcademicYear{} = year, %Date{} = date) do
    year
    |> list_sequences()
    |> Enum.find(fn s -> Date.compare(date, s.start_date) != :lt and Date.compare(date, s.end_date) != :gt end)
  end

  def create_teaching_context(%PersonalWorkspace{} = ws, %AcademicYear{} = year, attrs) do
    attrs = attrs |> Map.put(:personal_workspace_id, ws.id) |> Map.put(:academic_year_id, year.id)
    TeachingContext |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def list_teaching_contexts(%PersonalWorkspace{id: ws_id}, %AcademicYear{id: year_id}) do
    TeachingContext
    |> Ash.Query.filter(personal_workspace_id == ^ws_id and academic_year_id == ^year_id)
    |> Ash.Query.sort(subject: :asc)
    |> Ash.read!(authorize?: false)
  end

  def get_teaching_context(id), do: Ash.get(TeachingContext, id, authorize?: false)

  def create_progression_plan(%TeachingContext{} = ctx, attrs) do
    attrs =
      attrs
      |> Map.put(:teaching_context_id, ctx.id)
      |> Map.put(:academic_year_id, ctx.academic_year_id)
      |> Map.put(:personal_workspace_id, ctx.personal_workspace_id)

    ProgressionPlan |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end

  def list_progression_plans(%PersonalWorkspace{id: ws_id}) do
    ProgressionPlan
    |> Ash.Query.filter(personal_workspace_id == ^ws_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(authorize?: false)
  end

  def get_progression_plan(id), do: Ash.get(ProgressionPlan, id, authorize?: false)

  def duplicate_progression_plan(%ProgressionPlan{} = plan, overrides) do
    attrs =
      %{
        title: Map.get(overrides, :title, plan.title <> " (copy)"),
        status: :draft,
        template: Map.get(overrides, :template, false),
        teaching_context_id: plan.teaching_context_id,
        academic_year_id: plan.academic_year_id,
        personal_workspace_id: plan.personal_workspace_id
      }

    ProgressionPlan |> Ash.Changeset.for_create(:create, attrs) |> Ash.create(authorize?: false)
  end
end
