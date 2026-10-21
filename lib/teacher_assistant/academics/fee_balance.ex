defmodule TeacherAssistant.Academics.FeeBalance do
  @moduledoc """
  Fee arithmetic (Fees 1), pure: what each fee type costs a student, how a payment is
  split across fee types in payment order, the student's balance against the
  school-wide cumulative tranches, and the recovery figures. Amounts are integer FCFA;
  fee types are any ids, given in payment order.
  """

  @doc """
  A student's due per fee type: the class amount (or, for the arrears type, the
  carried arrears) minus the student's adjustment for that type, never below zero.
  """
  def dues(type_ids, class_amounts, arrears, arrears_type_id, adjustments) do
    Map.new(type_ids, fn id ->
      base = if id == arrears_type_id, do: arrears, else: Map.get(class_amounts, id, 0)
      {id, max(base - Map.get(adjustments, id, 0), 0)}
    end)
  end

  @doc """
  Splits `amount` across `ordered_type_ids`: each type takes what is still owed on it,
  in order; whatever is left after the last type (an overpayment) goes to the last
  type. Returns `[{type_id, amount}]` without zero entries.
  """
  def allocate(amount, [_ | _] = ordered_type_ids, due, paid) do
    {shares, left} =
      Enum.map_reduce(ordered_type_ids, amount, fn id, left ->
        owed = max(Map.get(due, id, 0) - Map.get(paid, id, 0), 0)
        share = min(left, owed)
        {{id, share}, left - share}
      end)

    shares
    |> List.update_at(-1, fn {id, share} -> {id, share + left} end)
    |> Enum.reject(fn {_id, share} -> share == 0 end)
  end

  @doc """
  The student's balance as of `on_date`: per type (due, paid, left) and in total.
  `due_to_date` is the total due times the percent of the latest tranche already due
  (0 before the first); `status` is `:paid_up`, `:on_track` or `:behind`.
  """
  def balance(ordered_type_ids, due, paid, tranches, on_date) do
    by_type =
      Enum.map(ordered_type_ids, fn id ->
        d = Map.get(due, id, 0)
        p = Map.get(paid, id, 0)
        %{type_id: id, due: d, paid: p, left: d - p}
      end)

    total_due = by_type |> Enum.map(& &1.due) |> Enum.sum()
    total_paid = by_type |> Enum.map(& &1.paid) |> Enum.sum()
    due_to_date = div(total_due * percent_due(tranches, on_date), 100)
    left = total_due - total_paid

    %{
      by_type: by_type,
      total_due: total_due,
      total_paid: total_paid,
      left: left,
      due_to_date: due_to_date,
      status: status(left, total_paid, due_to_date)
    }
  end

  @doc """
  What a student owes toward the tranches due, per fee type (Fees 2 warnings): what is
  due to date minus what was paid, spread over the types in payment order, each capped
  at what is still unpaid on it — the way the next payment would be allocated, so the
  rows always add up to the student's « reste ». Returns `[%{type_id, amount}]` without
  zero rows.
  """
  def overdue_by_type(%{by_type: by_type, due_to_date: due_to_date} = balance) do
    owed = max(due_to_date - balance.total_paid, 0)

    {rows, _left} =
      Enum.map_reduce(by_type, owed, fn %{type_id: id, due: due, paid: paid}, left ->
        share = min(max(due - paid, 0), left)
        {%{type_id: id, amount: share}, left - share}
      end)

    Enum.reject(rows, &(&1.amount == 0))
  end

  defp percent_due(tranches, on_date) do
    tranches
    |> Enum.filter(&(Date.compare(&1.due_date, on_date) != :gt))
    |> Enum.map(& &1.percent)
    |> Enum.max(fn -> 0 end)
  end

  defp status(left, _paid, _due_to_date) when left <= 0, do: :paid_up
  defp status(_left, paid, due_to_date) when paid >= due_to_date, do: :on_track
  defp status(_left, _paid, _due_to_date), do: :behind

  @doc "Recovery figures over students' balances; rates are whole percents (0 with nothing expected)."
  def recovery(balances) do
    expected = sum(balances, :total_due)
    expected_to_date = sum(balances, :due_to_date)
    collected = sum(balances, :total_paid)

    %{
      students: length(balances),
      expected: expected,
      expected_to_date: expected_to_date,
      collected: collected,
      rate: rate(collected, expected),
      rate_to_date: rate(collected, expected_to_date),
      behind: Enum.count(balances, &(&1.status == :behind))
    }
  end

  defp sum(balances, key), do: balances |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()

  defp rate(_part, 0), do: 0
  defp rate(part, whole), do: div(part * 100, whole)
end
