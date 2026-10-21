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
    FeeSendOut,
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
    e = Ash.load!(e, [:student, :class_group], scope: scope)

    resource
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{
        enrollment_id: e.id,
        academic_year_id: year.id,
        seq: seq,
        number:
          "#{prefix}#{year.start_date.year}-#{String.pad_leading(Integer.to_string(seq), 6, "0")}",
        student_name: e.student.full_name,
        class_label: e.class_group.label,
        issued_by_user_id: scope.current_user && scope.current_user.id
      }),
      scope: scope
    )
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
