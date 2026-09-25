defmodule TeacherAssistant.Organization do
  use Ash.Domain, otp_app: :teacher_assistant

  alias TeacherAssistant.Academics.{AcademicYear, Sequence, Term, Workspace}
  alias TeacherAssistant.Accounts.SchoolMembership
  alias TeacherAssistant.Scope

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
      define :get_workspace, action: :read, get_by: [:id]
    end

    resource AcademicYear
    resource Term
    resource Sequence
  end

  authorization do
    authorize :when_requested
  end

  @doc """
  Creates a school workspace with its profile, the creator's `:head`
  membership, and the seeded Subject catalog — all inside the
  `Workspace.:create_school` create transaction. Takes a scope carrying
  only the user (there is no school yet to scope to).
  """
  def create_school(%Scope{} = scope, %{} = attrs) do
    name = attrs[:name] || attrs["name"]

    Workspace
    |> Ash.Changeset.for_create(
      :create_school,
      %{
        name: name,
        owner_user_id: scope.current_user.id,
        profile: Map.take(attrs, @profile_keys)
      },
      scope: scope
    )
    |> Ash.create()
  end

  @doc """
  Every school the scope's user is an active member of, in membership order.

  Runs with no tenant: `SchoolMembership` is a `global? true` multitenant
  resource so this read (needed before any tenant is chosen) works across
  every school. Takes a scope carrying only the user.
  """
  def list_workspaces_for(%Scope{} = scope) do
    SchoolMembership
    |> Ash.Query.for_read(:active_for_user, %{user_id: scope.current_user.id}, scope: scope)
    |> Ash.read!()
    |> Enum.map(& &1.workspace)
  end

  # --- Academic calendar (AcademicYear / Term / Sequence) -------------------

  def create_academic_year(%Scope{} = scope, attrs) do
    attrs = Map.put_new(attrs, :active, true)

    AcademicYear
    |> Ash.Changeset.for_create(:create_for_workspace, attrs, scope: scope)
    |> Ash.create()
  end

  def list_academic_years(%Scope{} = scope) do
    AcademicYear
    |> Ash.Query.for_read(:for_workspace, %{}, scope: scope)
    |> Ash.read!()
  end

  def current_academic_year(%Scope{} = scope) do
    AcademicYear
    |> Ash.Query.for_read(:active_for_workspace, %{}, scope: scope)
    |> Ash.read!()
    |> List.first()
  end

  @doc """
  Fetches an academic year by id, scoped to the scope's tenant (IDOR guard):
  a year that belongs to a different workspace is invisible, same as any
  other cross-tenant read.
  """
  def get_academic_year(%Scope{} = scope, id) do
    Ash.get(AcademicYear, id, scope: scope)
  end

  @doc """
  Activates `year` and deactivates every other active year of the same
  workspace (see `AcademicYear`'s `:activate` action).
  """
  def activate_academic_year(%Scope{} = scope, %AcademicYear{} = year) do
    year
    |> Ash.Changeset.for_update(:activate, %{}, scope: scope)
    |> Ash.update()
  end

  @doc """
  Seeds a year's default calendar (3 terms, their séquences) — idempotent, no-op once séquences exist — from
  `Reference.default_calendar_preset/2` applied to the year's own dates. Not wrapped in a shared transaction
  (same as before the move) — each Term/Sequence create is its own action call.
  """
  def build_default_calendar(%Scope{} = scope, %AcademicYear{} = year) do
    if list_sequences(scope, year) == [], do: do_build_default_calendar(scope, year), else: :ok
  end

  defp do_build_default_calendar(%Scope{} = scope, year) do
    preset =
      TeacherAssistant.Academics.Reference.default_calendar_preset(year.start_date, year.end_date)

    Enum.each(preset.terms, fn term_spec ->
      {:ok, term} =
        Term
        |> Ash.Changeset.for_create(
          :create,
          %{
            position: term_spec.position,
            academic_year_id: year.id
          },
          scope: scope
        )
        |> Ash.create()

      Enum.each(term_spec.sequences, fn s ->
        Sequence
        |> Ash.Changeset.for_create(
          :create,
          s
          |> Map.take([:number, :position_in_term, :start_date, :end_date, :integration_week])
          |> Map.put(:term_id, term.id),
          scope: scope
        )
        |> Ash.create!()
      end)
    end)

    :ok
  end

  def list_sequences(%Scope{} = scope, %AcademicYear{id: year_id}) do
    Sequence
    |> Ash.Query.for_read(:for_academic_year, %{academic_year_id: year_id}, scope: scope)
    |> Ash.read!()
  end

  def list_terms(%Scope{} = scope, %AcademicYear{id: year_id}) do
    Term
    |> Ash.Query.for_read(:for_academic_year, %{academic_year_id: year_id}, scope: scope)
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

  def resolve_period(%Scope{} = _scope, %AcademicYear{} = year, "annee"), do: {:annual, year}

  def resolve_period(%Scope{} = scope, %AcademicYear{} = year, "seq:" <> id) do
    case Enum.find(list_sequences(scope, year), &(&1.id == id)) do
      nil -> nil
      seq -> {:sequence, seq}
    end
  end

  def resolve_period(%Scope{} = scope, %AcademicYear{} = year, "trim:" <> id) do
    case Enum.find(list_terms(scope, year), &(&1.id == id)) do
      nil -> nil
      term -> {:trimester, term}
    end
  end

  def resolve_period(%Scope{} = _scope, _year, _param), do: nil

  def period_date_range(
        %Scope{} = _scope,
        {:sequence, %Sequence{start_date: start, end_date: last}}
      ) do
    {start, last}
  end

  def period_date_range(%Scope{} = _scope, {:trimester, %Term{sequences: sequences}}) do
    sequence_date_range(sequences)
  end

  def period_date_range(%Scope{} = scope, {:annual, %AcademicYear{} = year}) do
    sequence_date_range(list_sequences(scope, year))
  end

  defp sequence_date_range([]), do: nil

  defp sequence_date_range(sequences) do
    first = sequences |> Enum.map(& &1.start_date) |> Enum.min(Date)
    last = sequences |> Enum.map(& &1.end_date) |> Enum.max(Date)
    {first, last}
  end

  def current_sequence(%Scope{} = scope, %AcademicYear{} = year, %Date{} = date) do
    scope
    |> list_sequences(year)
    |> Enum.find(fn s ->
      Date.compare(date, s.start_date) != :lt and Date.compare(date, s.end_date) != :gt
    end)
  end
end
