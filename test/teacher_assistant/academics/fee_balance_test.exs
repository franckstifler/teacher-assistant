defmodule TeacherAssistant.Academics.FeeBalanceTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.{FeeBalance, FeeTranche, Payment}

  describe "compute/4" do
    test "due_to_date sums only tranches due on/before on_date, excluding a future-dated tranche" do
      tranches = [
        %FeeTranche{amount: 10_000, due_date: ~D[2025-09-15]},
        %FeeTranche{amount: 20_000, due_date: ~D[2025-12-15]}
      ]

      result = FeeBalance.compute(tranches, [], 0, ~D[2025-10-01])

      assert result.total_due == 30_000
      assert result.due_to_date == 10_000
    end

    test ":on_track when total_paid exactly equals due_to_date" do
      tranches = [
        %FeeTranche{amount: 10_000, due_date: ~D[2025-09-15]},
        %FeeTranche{amount: 20_000, due_date: ~D[2025-12-15]}
      ]

      payments = [%Payment{amount: 10_000}]

      result = FeeBalance.compute(tranches, payments, 0, ~D[2025-10-01])

      assert result.due_to_date == 10_000
      assert result.total_paid == 10_000
      assert result.status == :on_track
    end

    test ":behind when total_paid is exactly one FCFA under due_to_date" do
      tranches = [
        %FeeTranche{amount: 10_000, due_date: ~D[2025-09-15]},
        %FeeTranche{amount: 20_000, due_date: ~D[2025-12-15]}
      ]

      payments = [%Payment{amount: 9_999}]

      result = FeeBalance.compute(tranches, payments, 0, ~D[2025-10-01])

      assert result.due_to_date == 10_000
      assert result.total_paid == 9_999
      assert result.status == :behind
    end

    test ":paid_up on overpayment, with a negative balance" do
      tranches = [
        %FeeTranche{amount: 10_000, due_date: ~D[2025-09-15]}
      ]

      payments = [%Payment{amount: 15_000}]

      result = FeeBalance.compute(tranches, payments, 0, ~D[2025-10-01])

      assert result.total_due == 10_000
      assert result.total_paid == 15_000
      assert result.balance == -5_000
      assert result.status == :paid_up
    end

    test "adjustment_amount reduces total_due and due_to_date, both floored at 0" do
      tranches = [
        %FeeTranche{amount: 10_000, due_date: ~D[2025-09-15]},
        %FeeTranche{amount: 20_000, due_date: ~D[2025-12-15]}
      ]

      result = FeeBalance.compute(tranches, [], 50_000, ~D[2025-10-01])

      assert result.total_due == 0
      assert result.due_to_date == 0
    end

    test "due_to_date includes a tranche due exactly on on_date, excludes one due the day after" do
      tranches = [
        %FeeTranche{amount: 10_000, due_date: ~D[2025-10-01]},
        %FeeTranche{amount: 20_000, due_date: ~D[2025-10-02]}
      ]

      result = FeeBalance.compute(tranches, [], 0, ~D[2025-10-01])

      assert result.total_due == 30_000
      assert result.due_to_date == 10_000
    end

    test "empty tranches and payments yield an all-zero map and :paid_up" do
      result = FeeBalance.compute([], [], 0, ~D[2025-10-01])

      assert result == %{
               total_due: 0,
               total_paid: 0,
               balance: 0,
               due_to_date: 0,
               status: :paid_up
             }
    end
  end
end
