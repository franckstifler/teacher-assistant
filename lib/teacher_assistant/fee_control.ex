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
    ReturnNote
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
end
