defmodule TeacherAssistant.Academics.FeeBalance do
  @moduledoc """
  Pure, deterministic fee balance arithmetic (total due, total paid, balance,
  amount due to date, payment status). No database access — operates on
  plain structs/maps, like `Academics.Conduct`.
  """

  @doc """
  Computes the fee balance for a list of `%FeeTranche{}` (with `amount`,
  `due_date`) and `%Payment{}` (with `amount`) structs, given an integer
  `adjustment_amount` and the `on_date` cutoff (a `Date`).

  Returns `%{total_due, total_paid, balance, due_to_date, status}`, all
  integer FCFA amounts except `status`, which is one of `:paid_up`,
  `:on_track`, `:behind`.
  """
  def compute(tranches, payments, adjustment_amount, on_date) do
    total_tranches = sum_amounts(tranches)
    total_due = max(0, total_tranches - adjustment_amount)
    total_paid = sum_amounts(payments)
    balance = total_due - total_paid

    due_sum_to_date =
      tranches
      |> Enum.filter(&(Date.compare(&1.due_date, on_date) != :gt))
      |> sum_amounts()

    due_to_date = min(total_due, max(0, due_sum_to_date - adjustment_amount))

    status =
      cond do
        balance <= 0 -> :paid_up
        total_paid >= due_to_date -> :on_track
        true -> :behind
      end

    %{
      total_due: total_due,
      total_paid: total_paid,
      balance: balance,
      due_to_date: due_to_date,
      status: status
    }
  end

  defp sum_amounts(items), do: Enum.reduce(items, 0, &(&1.amount + &2))
end
