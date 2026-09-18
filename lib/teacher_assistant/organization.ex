defmodule TeacherAssistant.Organization do
  use Ash.Domain, otp_app: :teacher_assistant

  alias TeacherAssistant.Academics.{AcademicYear, Sequence, Term, Workspace}
  alias TeacherAssistant.Accounts.{SchoolMembership, User}

  @profile_keys [
    :short_name,
    :school_type,
    :subsystem,
    :sector,
    :region,
    :department,
    :town,
    :phone,
    :email,
    :address,
    :head_name,
    :motto,
    :registration_number
  ]

  authorization do
    authorize :when_requested
  end

  resources do
    resource Workspace do
      define :rename_school, action: :update, args: [:name]
      define :get_personal_workspace, action: :read, get_by: [:id]
    end

    resource AcademicYear do
      define :get_academic_year, action: :read, get_by: [:id]
      define :activate_academic_year, action: :activate
    end

    resource Term
    resource Sequence
  end

  @doc """
  Creates a school workspace with its profile, the creator's `:head`
  membership, and the seeded Subject catalog — all inside the
  `Workspace.:create_school` create transaction.
  """
  def create_school(%User{} = user, %{} = attrs) do
    name = attrs[:name] || attrs["name"]

    Workspace
    |> Ash.Changeset.for_create(:create_school, %{
      name: name,
      owner_user_id: user.id,
      profile: Map.take(attrs, @profile_keys)
    })
    |> Ash.create()
  end

  @doc """
  The user's personal workspace followed by every school they are an active
  member of.
  """
  def list_workspaces_for(%User{} = user) do
    personal = ensure_personal_workspace!(user)

    schools =
      SchoolMembership
      |> Ash.Query.for_read(:active_for_user, %{user_id: user.id})
      |> Ash.read!()
      |> Enum.map(& &1.workspace)

    [personal | schools]
  end

  # --- Personal workspace ---------------------------------------------------

  @doc """
  The current user's own (`:personal`) workspace, creating it on first use.
  Idempotent per user (`Workspace`'s `unique_owner_user` identity).
  """
  def ensure_personal_workspace!(%User{} = user) do
    case personal_workspace_for_user(user) do
      {:ok, ws} ->
        ws

      {:error, :not_found} ->
        Workspace
        |> Ash.Changeset.for_create(:create, %{
          name: "Personal workspace",
          kind: :personal,
          owner_user_id: user.id
        })
        |> Ash.create!()
    end
  end

  defp personal_workspace_for_user(%User{id: user_id}) do
    Workspace
    |> Ash.Query.for_read(:for_owner, %{owner_user_id: user_id})
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  # --- Academic calendar (AcademicYear / Term / Sequence) -------------------

  def create_academic_year(%Workspace{} = ws, attrs) do
    attrs = attrs |> Map.put(:workspace_id, ws.id) |> Map.put_new(:active, true)

    AcademicYear
    |> Ash.Changeset.for_create(:create_for_workspace, attrs)
    |> Ash.create()
  end

  def list_academic_years(%Workspace{id: ws_id}) do
    AcademicYear
    |> Ash.Query.for_read(:for_workspace, %{workspace_id: ws_id})
    |> Ash.read!()
  end

  def current_academic_year(%Workspace{id: ws_id}) do
    AcademicYear
    |> Ash.Query.for_read(:active_for_workspace, %{workspace_id: ws_id})
    |> Ash.read!()
    |> List.first()
  end

  @doc """
  Seeds a year's default calendar (3 terms, their séquences) from
  `Reference.default_calendar_preset/0`. Not wrapped in a shared transaction
  (same as before the move) — each Term/Sequence create is its own action call.
  """
  def build_default_calendar(%AcademicYear{} = year) do
    preset = TeacherAssistant.Academics.Reference.default_calendar_preset()

    Enum.each(preset.terms, fn term_spec ->
      {:ok, term} =
        Term
        |> Ash.Changeset.for_create(:create, %{
          position: term_spec.position,
          academic_year_id: year.id
        })
        |> Ash.create()

      Enum.each(term_spec.sequences, fn s ->
        Sequence
        |> Ash.Changeset.for_create(
          :create,
          Map.put(
            Map.take(s, [:number, :position_in_term, :start_date, :end_date, :integration_week]),
            :term_id,
            term.id
          )
        )
        |> Ash.create!()
      end)
    end)

    :ok
  end

  def list_sequences(%AcademicYear{id: year_id}) do
    Sequence
    |> Ash.Query.for_read(:for_academic_year, %{academic_year_id: year_id})
    |> Ash.read!()
  end

  def list_terms(%AcademicYear{id: year_id}) do
    Term
    |> Ash.Query.for_read(:for_academic_year, %{academic_year_id: year_id})
    |> Ash.read!()
  end
end
