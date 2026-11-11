defmodule TeacherAssistant.Organization do
  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

  alias TeacherAssistant.Academics.{
    AcademicYear,
    CalendarRules,
    Holiday,
    Room,
    SchoolCalendar,
    Sequence,
    Term,
    Workspace
  }

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
    resource Holiday
    resource Room
  end

  authorization do
    authorize :by_default
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
      %{name: name, profile: Map.take(attrs, @profile_keys)},
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

  @doc "Replaces a school's modules (operator only, journaled)."
  def set_modules(%Scope{} = scope, %Workspace{} = ws, modules) when is_list(modules) do
    ws
    |> Ash.Changeset.for_update(:set_modules, %{modules: modules}, scope: scope)
    |> Ash.update()
  end

  @doc "Suspends a school with a reason (operator only, journaled)."
  def suspend_school(%Scope{} = scope, %Workspace{} = ws, reason) do
    ws |> Ash.Changeset.for_update(:suspend, %{reason: reason}, scope: scope) |> Ash.update()
  end

  @doc "Lifts a school's suspension (operator only, journaled)."
  def reactivate_school(%Scope{} = scope, %Workspace{} = ws) do
    ws |> Ash.Changeset.for_update(:reactivate, %{}, scope: scope) |> Ash.update()
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

  @doc "Spec KLM9: the year a class (or any record with `academic_year_id`) belongs to."
  def class_year(%Scope{current_academic_year: %AcademicYear{id: id} = year}, %{
        academic_year_id: id
      }),
      do: year

  def class_year(%Scope{} = scope, %{academic_year_id: id}) when is_binary(id) do
    case get_academic_year(scope, id) do
      {:ok, year} -> year
      _ -> nil
    end
  end

  def class_year(_scope, _record), do: nil

  @doc """
  Activates `year` and deactivates every other active year of the same
  workspace (see `AcademicYear`'s `:activate` action).
  """
  def activate_academic_year(%Scope{} = scope, %AcademicYear{} = year) do
    year
    |> Ash.Changeset.for_update(:activate, %{}, scope: scope)
    |> Ash.update()
  end

  @doc "Spec KLM9: closes `year` for good (read only from then on). Called by `NewYear.start/3`."
  def close_academic_year(%Scope{} = scope, %AcademicYear{} = year) do
    year
    |> Ash.Changeset.for_update(:close, %{}, scope: scope)
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

    Enum.reduce_while(preset.terms, :ok, fn term_spec, :ok ->
      with {:ok, term} <-
             Term
             |> Ash.Changeset.for_create(
               :create,
               %{position: term_spec.position, academic_year_id: year.id},
               scope: scope
             )
             |> Ash.create(),
           :ok <- create_sequences(scope, term, term_spec.sequences) do
        {:cont, :ok}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp create_sequences(%Scope{} = scope, term, sequence_specs) do
    Enum.reduce_while(sequence_specs, :ok, fn s, :ok ->
      Sequence
      |> Ash.Changeset.for_create(
        :create,
        s
        |> Map.take([:number, :position_in_term, :start_date, :end_date, :integration_week])
        |> Map.put(:term_id, term.id),
        scope: scope
      )
      |> Ash.create()
      |> case do
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  @doc "Whether the scope may manage academic years and calendars (admin axis)."
  def can_manage_calendar?(scope), do: Ash.can?({AcademicYear, :create_for_workspace}, scope)

  @doc "Whether the scope may rename its school (head)."
  def can_rename_school?(%{current_workspace: %Workspace{} = ws} = scope),
    do: Ash.can?({ws, :update}, scope)

  def can_rename_school?(_scope), do: false

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

  @doc """
  Saves a year's whole calendar — séquence dates, grade-entry deadlines and
  trimester class-council dates — in one transaction, after `CalendarRules`
  accepts the complete proposed calendar (so a later row can never be written
  against a stale neighbour).

  `params` is form-shaped and string-keyed:
  `%{"sequences" => %{id => %{"start_date" => "2026-09-07", "end_date" => …,
  "entry_deadline" => …}}, "terms" => %{id => %{"class_council_date" => …}}}`.
  A missing key keeps the stored value; `""` blanks it. Authorization is the
  per-row update policy (admin axis): a forbidden row rolls back every write.
  """
  def update_calendar(%Scope{} = scope, %AcademicYear{} = year, %{} = params) do
    terms = list_terms(scope, year)
    seq_params = Map.get(params, "sequences", %{})
    term_params = Map.get(params, "terms", %{})

    sequences =
      for term <- terms, seq <- term.sequences do
        p = Map.get(seq_params, seq.id, %{})

        %{
          record: seq,
          id: seq.id,
          number: seq.number,
          term_id: term.id,
          start_date: date_param(p, "start_date", seq.start_date),
          end_date: date_param(p, "end_date", seq.end_date),
          entry_deadline: date_param(p, "entry_deadline", seq.entry_deadline)
        }
      end

    proposed_terms =
      for term <- terms do
        p = Map.get(term_params, term.id, %{})

        %{
          record: term,
          id: term.id,
          class_council_date: date_param(p, "class_council_date", term.class_council_date)
        }
      end

    with :ok <- CalendarRules.validate(year, sequences, proposed_terms),
         {:ok, :ok} <-
           Ash.transact([Sequence, Term], fn ->
             with :ok <- update_rows(sequences, [:start_date, :end_date, :entry_deadline], scope) do
               update_rows(proposed_terms, [:class_council_date], scope)
             end
           end) do
      :ok
    end
  end

  defp date_param(params, key, current) do
    case Map.fetch(params, key) do
      :error ->
        current

      {:ok, ""} ->
        nil

      {:ok, value} when is_binary(value) ->
        case Date.from_iso8601(value) do
          {:ok, date} -> date
          {:error, _} -> :invalid
        end
    end
  end

  defp update_rows(rows, fields, scope) do
    Enum.reduce_while(rows, :ok, fn row, :ok ->
      row.record
      |> Ash.Changeset.for_update(:update, Map.take(row, fields), scope: scope)
      |> Ash.update()
      |> case do
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
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

  @doc """
  Whether a trimester or the year is « en cours » (spec A4): some of its séquences
  have not started yet, so its figures cover what exists so far. A séquence never is.
  """
  def period_in_progress?(%Scope{} = _scope, {:sequence, _}), do: false

  def period_in_progress?(%Scope{} = scope, period),
    do:
      scope
      |> period_sequences(period)
      |> Enum.any?(&TeacherAssistant.Academics.Lock.not_started?/1)

  @doc "A period's séquences: the séquence itself, the trimester's, or the year's."
  def period_sequences(%Scope{} = _scope, {:sequence, %Sequence{} = seq}), do: [seq]

  def period_sequences(%Scope{} = scope, {:trimester, %Term{} = term}) do
    case term.sequences do
      %Ash.NotLoaded{} -> list_sequences_of_term(scope, term)
      loaded -> loaded
    end
  end

  def period_sequences(%Scope{} = scope, {:annual, %AcademicYear{} = year}),
    do: list_sequences(scope, year)

  @doc """
  The day a period's class is counted on (A7): its first séquence's start — for the
  year, the last trimester's (the T3 bulletin carries the annual line). A student who
  left before it is not in the period; one who left on or after it is. Without
  séquences, today.
  """
  def period_first_day(%Scope{} = _scope, {:sequence, %Sequence{start_date: start}}), do: start

  def period_first_day(%Scope{} = scope, {:trimester, %Term{}} = period),
    do: scope |> period_sequences(period) |> first_start()

  def period_first_day(%Scope{} = scope, {:annual, %AcademicYear{} = year}) do
    case scope |> list_terms(year) |> List.last() do
      nil -> first_start([])
      last_term -> first_start(last_term.sequences)
    end
  end

  defp first_start([]), do: TeacherAssistant.Academics.Reference.today()
  defp first_start(sequences), do: sequences |> Enum.map(& &1.start_date) |> Enum.min(Date)

  defp list_sequences_of_term(scope, %Term{id: term_id, academic_year_id: year_id}) do
    Sequence
    |> Ash.Query.filter(term_id == ^term_id and term.academic_year_id == ^year_id)
    |> Ash.read!(scope: scope)
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

  # --- Rooms (spec J3) -------------------------------------------------------------

  @doc "The school's rooms, by name."
  def list_rooms(%Scope{} = scope) do
    Room |> Ash.Query.for_read(:for_workspace, %{}, scope: scope) |> Ash.read!()
  end

  @doc "The rooms that can still be chosen (home room, default room, a lesson's room)."
  def list_active_rooms(%Scope{} = scope), do: scope |> list_rooms() |> Enum.filter(& &1.active?)

  def create_room(%Scope{} = scope, attrs) do
    Room |> Ash.Changeset.for_create(:create, attrs, scope: scope) |> Ash.create()
  end

  def update_room(%Scope{} = scope, %Room{} = room, attrs) do
    room |> Ash.Changeset.for_update(:update, attrs, scope: scope) |> Ash.update()
  end

  @doc "Deletes a room nothing uses (any year); `{:error, :in_use}` otherwise — deactivate it instead."
  def delete_room(%Scope{} = scope, %Room{} = room) do
    if room_in_use?(scope, room), do: {:error, :in_use}, else: Ash.destroy(room, scope: scope)
  end

  @room_users [
    {TeacherAssistant.Academics.TimetableSlot, :room_id},
    {TeacherAssistant.Academics.ClassGroup, :home_room_id},
    {TeacherAssistant.Academics.Subject, :default_room_id}
  ]

  @doc "Whether a lesson, a class (home room) or a subject (default room) of any year uses the room."
  def room_in_use?(%Scope{} = scope, %Room{id: id}) do
    Enum.any?(@room_users, fn {resource, field} ->
      resource
      |> Ash.Query.do_filter([{field, id}])
      |> Ash.exists?(scope: scope)
    end)
  end

  @doc "The ids of every room a lesson, a class or a subject of any year uses: one query per kind."
  def rooms_in_use(%Scope{} = scope) do
    for {resource, field} <- @room_users,
        record <-
          resource
          |> Ash.Query.do_filter(not: [{field, [is_nil: true]}])
          |> Ash.Query.select([field])
          |> Ash.Query.distinct(field)
          |> Ash.read!(scope: scope),
        into: MapSet.new(),
        do: Map.fetch!(record, field)
  end

  # --- Holidays (spec J1) ---------------------------------------------------------

  def list_holidays(%Scope{} = scope, %AcademicYear{id: year_id}) do
    Holiday
    |> Ash.Query.for_read(:for_year, %{academic_year_id: year_id}, scope: scope)
    |> Ash.read!()
  end

  def create_holiday(%Scope{} = scope, %AcademicYear{id: year_id}, attrs) do
    Holiday
    |> Ash.Changeset.for_create(:create, Map.put(attrs, :academic_year_id, year_id), scope: scope)
    |> Ash.create()
  end

  def update_holiday(%Scope{} = scope, %Holiday{} = holiday, attrs) do
    holiday |> Ash.Changeset.for_update(:update, attrs, scope: scope) |> Ash.update()
  end

  def delete_holiday(%Scope{} = scope, %Holiday{} = holiday),
    do: Ash.destroy(holiday, scope: scope)

  @doc "Adds the year's national holidays whose date no holiday covers yet. `{:ok, added}`."
  def prefill_holidays(%Scope{} = scope, %AcademicYear{} = year) do
    # A date any existing holiday already covers is skipped, whatever its label or
    # the language it was typed in (« Noël » folded into « Congés de Noël », …).
    existing =
      SchoolCalendar.new(
        nil,
        false,
        Enum.map(list_holidays(scope, year), &Map.take(&1, [:label, :start_date, :end_date]))
      )

    year.start_date
    |> SchoolCalendar.national_holidays(year.end_date)
    |> Enum.reject(&SchoolCalendar.holiday_on(existing, &1.start_date))
    |> Enum.reduce_while({:ok, 0}, fn h, {:ok, n} ->
      case create_holiday(scope, year, h) do
        {:ok, _} -> {:cont, {:ok, n + 1}}
        error -> {:halt, error}
      end
    end)
  end
end
