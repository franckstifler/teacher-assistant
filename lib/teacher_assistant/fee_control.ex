defmodule TeacherAssistant.FeeControl do
  @moduledoc """
  Fees 2: the bursar's rounds. The « Contrôle des frais » list of one class (who must
  leave, who may stay although late and why), the day's send-outs that roll calls show
  as « Renvoyé pour frais », return notes and warnings to parents.
  """
  require Ash.Query

  alias TeacherAssistant.Fees
  alias TeacherAssistant.Scope

  alias TeacherAssistant.Academics.{
    AcademicYear,
    ClassGroup,
    Enrollment,
    FeeBalance,
    FeeSendOut,
    FeeWarning,
    Reference,
    ReturnNote,
    ReturnNoteReason
  }

  # --- Class control list ---------------------------------------------------------------

  @doc """
  The class's control list on `date`: `must_leave` (late, no valid note), `allowed`
  (late with a valid note), the count of students `up_to_date`, and the latest tranche
  due (nil before the first, when nobody is late). Each row: `%{enrollment, student,
  owed, note, sent_out?}`, `owed` being what is due by now minus what was paid.
  """
  def class_control(%Scope{} = scope, %ClassGroup{} = cg, date \\ Reference.today()) do
    roster = TeacherAssistant.Enrollment.list_roster(scope, cg)
    ids = Enum.map(roster, & &1.enrollment.id)
    balances = Fees.class_balances(scope, cg, date)
    notes = notes_by_enrollment(scope, ids)
    sent = sent_home_ids(scope, ids, date)

    {late, on_time} = Enum.split_with(roster, &(balances[&1.enrollment.id].status == :behind))

    rows =
      Enum.map(late, fn %{enrollment: e, student: s} ->
        b = balances[e.id]

        %{
          enrollment: e,
          student: s,
          owed: b.due_to_date - b.total_paid,
          note: valid_note(Map.get(notes, e.id, []), date),
          sent_out?: MapSet.member?(sent, e.id)
        }
      end)

    {allowed, must_leave} = Enum.split_with(rows, & &1.note)

    %{
      must_leave: must_leave,
      allowed: allowed,
      up_to_date: length(on_time),
      tranche: tranche_due(scope, cg.academic_year_id, date)
    }
  end

  @doc "The valid note covering `date` (the latest issued when several do), or nil."
  def valid_note(notes, %Date{} = date) do
    notes
    |> Enum.filter(
      &(&1.status == :valid and Date.compare(&1.issued_on, date) != :gt and
          Date.compare(&1.valid_until, date) != :lt)
    )
    |> Enum.max_by(& &1.seq, fn -> nil end)
  end

  defp notes_by_enrollment(_scope, []), do: %{}

  defp notes_by_enrollment(scope, ids),
    do:
      ids
      |> Fees.list_notes_for_enrollment_ids!(scope: scope)
      |> Enum.group_by(& &1.enrollment_id)

  defp tranche_due(scope, year_id, date) do
    scope
    |> Fees.list_tranches(%AcademicYear{id: year_id})
    |> Enum.filter(&(Date.compare(&1.due_date, date) != :gt))
    |> List.last()
  end

  # --- Send-outs ------------------------------------------------------------------------

  @doc "Records that the student left class on `date` (fees axis); an existing one is kept."
  def record_send_out(%Scope{} = scope, %Enrollment{} = e, date \\ Reference.today()) do
    case send_out(scope, e.id, date) do
      nil ->
        FeeSendOut
        |> Ash.Changeset.for_create(
          :create,
          %{
            enrollment_id: e.id,
            academic_year_id: e.academic_year_id,
            date: date,
            recorded_by_user_id: scope.current_user && scope.current_user.id
          },
          scope: scope
        )
        |> Ash.create()

      existing ->
        {:ok, existing}
    end
  end

  @doc "Removes the student's send-out on `date`, if any."
  def undo_send_out(%Scope{} = scope, %Enrollment{} = e, date \\ Reference.today()) do
    case send_out(scope, e.id, date) do
      nil -> :ok
      row -> Ash.destroy(row, scope: scope)
    end
  end

  @doc "The enrollment ids among `enrollment_ids` sent home on `date` (any member may ask)."
  def sent_home_ids(_scope, [], _date), do: MapSet.new()

  def sent_home_ids(%Scope{} = scope, enrollment_ids, %Date{} = date) do
    enrollment_ids
    |> Fees.list_send_outs_on!(date, scope: scope)
    |> MapSet.new(& &1.enrollment_id)
  end

  @doc "Lifts today's send-out once the student is no longer late (after a payment)."
  def lift_send_out_if_up_to_date(%Scope{} = scope, %Enrollment{} = e) do
    if Fees.student_fees(scope, e).status != :behind, do: undo_send_out(scope, e)
    :ok
  end

  defp send_out(scope, enrollment_id, date) do
    case Fees.list_send_outs_on!([enrollment_id], date, scope: scope) do
      [row | _] -> row
      [] -> nil
    end
  end

  # --- Return notes ---------------------------------------------------------------------

  @doc """
  Issues a numbered « Autorisation de retour en classe » (fees axis). `attrs`: `reason`
  (`:promise | :payment | :exemption`), `valid_until` (required for a promise; a payment
  defaults to the next tranche's due date, an exemption to the year's end), and an
  `internal_note` never printed. Lifts the student's send-out of today.
  """
  def issue_note(%Scope{} = scope, %Enrollment{} = e, attrs) do
    reason = attrs[:reason]
    today = Reference.today()

    with true <- reason in ReturnNoteReason.values() || {:error, :invalid_reason},
         {:ok, year} <- Ash.get(AcademicYear, e.academic_year_id, scope: scope),
         {:ok, valid_until} <- valid_until(scope, year, reason, attrs[:valid_until], today),
         {:ok, note} <-
           create_numbered(scope, ReturnNote, "A", e, year, %{
             reason: reason,
             issued_on: today,
             valid_until: valid_until,
             internal_note: blank_to_nil(attrs[:internal_note])
           }) do
      undo_send_out(scope, e, today)
      {:ok, note}
    end
  end

  defp valid_until(_scope, _year, :promise, nil, _today), do: {:error, :invalid_valid_until}

  defp valid_until(scope, year, :payment, nil, today) do
    scope
    |> Fees.list_tranches(year)
    |> Enum.find(&(Date.compare(&1.due_date, today) == :gt))
    |> case do
      nil -> {:ok, year.end_date}
      tranche -> {:ok, tranche.due_date}
    end
  end

  defp valid_until(_scope, year, :exemption, nil, _today), do: {:ok, year.end_date}

  defp valid_until(_scope, _year, _reason, %Date{} = date, today) do
    if Date.compare(date, today) == :lt, do: {:error, :invalid_valid_until}, else: {:ok, date}
  end

  defp valid_until(_scope, _year, _reason, _other, _today), do: {:error, :invalid_valid_until}

  @doc "Cancels a note (with a reason): the student is late again from now on."
  def cancel_note(%Scope{} = scope, %ReturnNote{} = note, reason), do: cancel(scope, note, reason)

  @doc "The student's notes, newest first."
  def list_notes(%Scope{} = scope, %Enrollment{id: id}),
    do: Fees.list_notes_for_enrollment_ids!([id], scope: scope)

  @doc "What the printed note shows; `{:error, :not_found}` outside the scope's reach."
  def note(%Scope{} = scope, id) do
    case Ash.get(ReturnNote, id, scope: scope) do
      {:ok, note} ->
        {:ok,
         %{
           note: note,
           school: scope.current_workspace,
           issued_by_name: Fees.user_name(note.issued_by_user_id)
         }}

      _ ->
        {:error, :not_found}
    end
  rescue
    Ash.Error.Invalid -> {:error, :not_found}
  end

  # --- Warnings -------------------------------------------------------------------------

  @doc "The pay-by date a warning proposes: a week from today."
  def default_pay_by, do: Date.add(Reference.today(), 7)

  @doc """
  Issues one numbered « Avis de retard de paiement » per student of `enrollments` who is
  late today (others are skipped), with what they owe per fee type frozen and the
  `pay_by` date. `{:error, :nothing_to_warn}` when nobody is late.
  """
  def issue_warnings(
        %Scope{} = scope,
        [%Enrollment{} = first | _] = enrollments,
        %Date{} = pay_by
      ) do
    today = Reference.today()

    with :ok <- check_pay_by(pay_by, today),
         :ok <- check_can_warn(scope),
         {:ok, year} <- Ash.get(AcademicYear, first.academic_year_id, scope: scope),
         [_ | _] = owing <- owing(scope, year, enrollments, today) do
      # Load every student and class once, before taking the lock.
      loaded = Ash.load!(Enum.map(owing, &elem(&1, 0)), [:student, :class_group], scope: scope)
      owing = Enum.zip_with(loaded, owing, fn e, {_e, lines} -> {e, lines} end)

      Ash.transact([FeeWarning], fn ->
        lock!("V", first.workspace_id, year.id)

        Enum.map(owing, fn {e, lines} ->
          attrs = %{
            issued_on: today,
            pay_by: pay_by,
            lines: lines,
            total: Enum.sum(Enum.map(lines, & &1.amount))
          }

          case insert_numbered(scope, FeeWarning, "V", e, year, attrs) do
            {:ok, warning} -> warning
            {:error, error} -> Ash.DataLayer.rollback([FeeWarning], error)
          end
        end)
      end)
    else
      [] -> {:error, :nothing_to_warn}
      error -> error
    end
  end

  def issue_warnings(_scope, [], _pay_by), do: {:error, :nothing_to_warn}

  defp check_pay_by(pay_by, today),
    do: if(Date.compare(pay_by, today) == :lt, do: {:error, :invalid_pay_by}, else: :ok)

  defp check_can_warn(scope),
    do:
      if(Ash.can?({FeeWarning, :create}, scope),
        do: :ok,
        else: {:error, Ash.Error.Forbidden.exception([])}
      )

  # `[{enrollment, [%{name, amount}]}]` for the late students, in the given order.
  defp owing(scope, year, enrollments, today) do
    names = scope |> Fees.list_fee_types(year) |> Map.new(&{&1.id, &1.name})
    balances = Fees.balances_for(scope, year, enrollments, today)

    enrollments
    |> Enum.filter(&(balances[&1.id].status == :behind))
    |> Enum.map(fn e ->
      lines =
        balances[e.id]
        |> FeeBalance.overdue_by_type()
        |> Enum.map(&%{name: names[&1.type_id], amount: &1.amount})

      {e, lines}
    end)
    |> Enum.reject(fn {_e, lines} -> lines == [] end)
  end

  @doc "Cancels a warning (with a reason)."
  def cancel_warning(%Scope{} = scope, %FeeWarning{} = warning, reason),
    do: cancel(scope, warning, reason)

  @doc "The student's warnings, newest first."
  def list_warnings(%Scope{} = scope, %Enrollment{id: id}),
    do: Fees.list_warnings_for_enrollment_ids!([id], scope: scope)

  @doc "`%{enrollment_id => latest valid warning}` among `enrollment_ids`."
  def latest_warnings(_scope, []), do: %{}

  def latest_warnings(%Scope{} = scope, enrollment_ids) do
    enrollment_ids
    |> Fees.list_warnings_for_enrollment_ids!(scope: scope)
    |> Enum.filter(&(&1.status == :valid))
    |> Enum.group_by(& &1.enrollment_id)
    |> Map.new(fn {id, ws} -> {id, Enum.max_by(ws, & &1.seq)} end)
  end

  @doc "What the printed warnings show, in the order of `ids` (unknown ids are left out)."
  def warnings(%Scope{} = scope, ids) do
    rows =
      FeeWarning
      |> Ash.Query.filter(id in ^ids)
      |> Ash.read!(scope: scope)
      |> Map.new(&{&1.id, &1})

    {:ok,
     ids
     |> Enum.map(&rows[&1])
     |> Enum.reject(&is_nil/1)
     |> Enum.map(
       &%{
         warning: &1,
         school: scope.current_workspace,
         issued_by_name: Fees.user_name(&1.issued_by_user_id)
       }
     )}
  end

  # --- Public checks (no actor) ---------------------------------------------------------

  @doc """
  The public check of a note: `{:valid | :expired | :cancelled, map}` with only what the
  note prints, or `:invalid`.
  """
  def note_verification(workspace_id, id) do
    case Ash.get(ReturnNote, id, tenant: workspace_id, authorize?: false, load: [:workspace]) do
      {:ok, n} ->
        {note_status(n),
         %{
           kind: :note,
           number: n.number,
           school_name: n.workspace.name,
           student_name: n.student_name,
           class_label: n.class_label,
           reason: n.reason,
           issued_on: n.issued_on,
           valid_until: n.valid_until
         }}

      _ ->
        :invalid
    end
  rescue
    Ash.Error.Invalid -> :invalid
  end

  defp note_status(%{status: :cancelled}), do: :cancelled

  defp note_status(note),
    do: if(Date.compare(note.valid_until, Reference.today()) == :lt, do: :expired, else: :valid)

  @doc "The public check of a warning: `{:valid | :cancelled, map}` or `:invalid`."
  def warning_verification(workspace_id, id) do
    case Ash.get(FeeWarning, id, tenant: workspace_id, authorize?: false, load: [:workspace]) do
      {:ok, w} ->
        {w.status,
         %{
           kind: :warning,
           number: w.number,
           school_name: w.workspace.name,
           student_name: w.student_name,
           class_label: w.class_label,
           issued_on: w.issued_on,
           pay_by: w.pay_by,
           lines: Enum.map(w.lines, &Map.take(&1, [:name, :amount])),
           total: w.total
         }}

      _ ->
        :invalid
    end
  rescue
    Ash.Error.Invalid -> :invalid
  end

  @doc "`[{workspace_id, id}]` of every school's note with this number (typed check)."
  def find_note_by_number(number), do: find_number("return_notes", number)

  @doc "`[{workspace_id, id}]` of every school's warning with this number (typed check)."
  def find_warning_by_number(number), do: find_number("fee_warnings", number)

  defp find_number(table, number) when is_binary(number) do
    import Ecto.Query

    TeacherAssistant.Repo.all(
      from p in table,
        where: p.number == ^(number |> String.trim() |> String.upcase()),
        select: {type(p.workspace_id, Ecto.UUID), type(p.id, Ecto.UUID)}
    )
  end

  # --- Numbered papers (shared by notes and warnings) -----------------------------------

  # Creates one numbered paper (`<prefix><start year>-000001`) under the same kind of
  # advisory lock as receipts, with the student's name and class frozen.
  defp create_numbered(scope, resource, prefix, e, year, attrs) do
    Ash.transact([resource], fn ->
      lock!(prefix, e.workspace_id, year.id)

      case insert_numbered(scope, resource, prefix, e, year, attrs) do
        {:ok, row} -> row
        {:error, error} -> Ash.DataLayer.rollback([resource], error)
      end
    end)
  end

  defp lock!(prefix, workspace_id, year_id),
    do:
      TeacherAssistant.Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
        "paper-#{prefix}:#{workspace_id}:#{year_id}"
      ])

  defp insert_numbered(scope, resource, prefix, e, year, attrs) do
    seq = Fees.next_seq(resource, e.workspace_id, year.id)
    e = Ash.load!(e, [:student, :class_group], scope: scope, lazy?: true)

    resource
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{enrollment_id: e.id, academic_year_id: year.id}),
      scope: scope
    )
    # Computed here, under the numbering lock — never action inputs.
    |> Ash.Changeset.force_change_attributes(%{
      seq: seq,
      number:
        "#{prefix}#{year.start_date.year}-#{String.pad_leading(Integer.to_string(seq), 6, "0")}",
      student_name: e.student.full_name,
      class_label: e.class_group.label,
      issued_by_user_id: scope.current_user && scope.current_user.id
    })
    |> Ash.create()
  end

  defp cancel(scope, row, reason) do
    case blank_to_nil(reason) do
      nil ->
        {:error, :reason_required}

      reason ->
        row
        |> Ash.Changeset.for_update(:cancel, %{reason: reason}, scope: scope)
        |> Ash.update()
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
