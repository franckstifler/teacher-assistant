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

  authorization do
    authorize :when_requested
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
  Every school the user is an active member of, in membership order.
  Personal workspaces are paused and never listed.
  """
  def list_workspaces_for(%User{} = user) do
    SchoolMembership
    |> Ash.Query.for_read(:active_for_user, %{user_id: user.id})
    |> Ash.read!()
    |> Enum.map(& &1.workspace)
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
  Seeds a year's default calendar (3 terms, their séquences) — idempotent, no-op once séquences exist — from
  `Reference.default_calendar_preset/2` applied to the year's own dates. Not wrapped in a shared transaction
  (same as before the move) — each Term/Sequence create is its own action call.
  """
  def build_default_calendar(%AcademicYear{} = year) do
    if list_sequences(year) == [], do: do_build_default_calendar(year), else: :ok
  end

  defp do_build_default_calendar(year) do
    preset =
      TeacherAssistant.Academics.Reference.default_calendar_preset(year.start_date, year.end_date)

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

  # --- Period resolution (séquence / trimester / annual) --------------------
  #
  # A "period" is a `{:sequence, %Sequence{}}`, `{:trimester, %Term{}}` or
  # `{:annual, %AcademicYear{}}` tuple: the unit over which marks, attendance
  # and discipline are aggregated. These helpers translate between a period and
  # its URL param (`period_param/1` / `resolve_period/2`), expose its kind and
  # calendar date span, and locate the séquence covering a given day.

  def period_kind({:sequence, _}), do: :sequence
  def period_kind({:trimester, _}), do: :trimester
  def period_kind({:annual, _}), do: :annual

  def period_param({:sequence, %Sequence{id: id}}), do: "seq:" <> id
  def period_param({:trimester, %Term{id: id}}), do: "trim:" <> id
  def period_param({:annual, _}), do: "annee"

  def resolve_period(%AcademicYear{} = year, "annee"), do: {:annual, year}

  def resolve_period(%AcademicYear{} = year, "seq:" <> id) do
    case Enum.find(list_sequences(year), &(&1.id == id)) do
      nil -> nil
      seq -> {:sequence, seq}
    end
  end

  def resolve_period(%AcademicYear{} = year, "trim:" <> id) do
    case Enum.find(list_terms(year), &(&1.id == id)) do
      nil -> nil
      term -> {:trimester, term}
    end
  end

  def resolve_period(_year, _param), do: nil

  def period_date_range({:sequence, %Sequence{start_date: start_date, end_date: end_date}}) do
    {start_date, end_date}
  end

  def period_date_range({:trimester, %Term{sequences: sequences}}) do
    sequence_date_range(sequences)
  end

  def period_date_range({:annual, %AcademicYear{} = year}) do
    sequence_date_range(list_sequences(year))
  end

  defp sequence_date_range([]), do: nil

  defp sequence_date_range(sequences) do
    first = sequences |> Enum.map(& &1.start_date) |> Enum.min(Date)
    last = sequences |> Enum.map(& &1.end_date) |> Enum.max(Date)
    {first, last}
  end

  def current_sequence(%AcademicYear{} = year, %Date{} = date) do
    year
    |> list_sequences()
    |> Enum.find(fn s ->
      Date.compare(date, s.start_date) != :lt and Date.compare(date, s.end_date) != :gt
    end)
  end
end
