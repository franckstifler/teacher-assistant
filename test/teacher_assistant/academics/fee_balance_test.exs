defmodule TeacherAssistant.Academics.FeeBalanceTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.FeeBalance, as: B

  @types [:fe, :pta]
  @tranches [%{due_date: ~D[2025-10-15], percent: 40}, %{due_date: ~D[2026-01-15], percent: 100}]

  test "dues subtract adjustments per type and never go below zero" do
    assert B.dues(@types, %{fe: 50_000, pta: 10_000}, 0, nil, %{pta: 15_000}) ==
             %{fe: 50_000, pta: 0}

    assert B.dues([:arr | @types], %{fe: 50_000}, 7_000, :arr, %{}) ==
             %{arr: 7_000, fe: 50_000, pta: 0}
  end

  test "allocation fills types in order: 20_000 on 15_000 + 25_000 gives 15_000 then 5_000" do
    assert B.allocate(20_000, @types, %{fe: 15_000, pta: 25_000}, %{}) == [fe: 15_000, pta: 5_000]
  end

  test "allocation skips a fully paid type" do
    assert B.allocate(3_000, @types, %{fe: 15_000, pta: 25_000}, %{fe: 15_000}) == [pta: 3_000]
  end

  test "an overpayment goes to the last type" do
    assert B.allocate(5_000, @types, %{fe: 10_000, pta: 0}, %{fe: 10_000}) == [pta: 5_000]
    assert B.allocate(12_000, @types, %{fe: 10_000, pta: 0}, %{}) == [fe: 10_000, pta: 2_000]
  end

  test "balance: due to date follows the latest passed cumulative percent" do
    due = %{fe: 80_000, pta: 20_000}
    assert B.balance(@types, due, %{}, @tranches, ~D[2025-10-01]).due_to_date == 0
    assert B.balance(@types, due, %{}, @tranches, ~D[2025-11-01]).due_to_date == 40_000
    assert B.balance(@types, due, %{}, @tranches, ~D[2026-02-01]).due_to_date == 100_000
  end

  test "status: paid up, on track, behind" do
    due = %{fe: 80_000, pta: 20_000}
    on = ~D[2025-11-01]
    assert B.balance(@types, due, %{fe: 80_000, pta: 20_000}, @tranches, on).status == :paid_up
    assert B.balance(@types, due, %{fe: 40_000}, @tranches, on).status == :on_track
    assert B.balance(@types, due, %{fe: 39_999}, @tranches, on).status == :behind
  end

  test "balance lists each type with due, paid and left, and the totals" do
    b = B.balance(@types, %{fe: 80_000, pta: 20_000}, %{fe: 50_000}, @tranches, ~D[2025-11-01])

    assert b.by_type == [
             %{type_id: :fe, due: 80_000, paid: 50_000, left: 30_000},
             %{type_id: :pta, due: 20_000, paid: 0, left: 20_000}
           ]

    assert {b.total_due, b.total_paid, b.left} == {100_000, 50_000, 50_000}
  end

  test "an overpaid balance has a negative left" do
    b =
      B.balance(
        @types,
        %{fe: 10_000, pta: 0},
        %{fe: 10_000, pta: 5_000},
        @tranches,
        ~D[2025-11-01]
      )

    assert b.left == -5_000 and b.status == :paid_up
  end

  test "recovery sums students and rounds rates down" do
    on = ~D[2025-11-01]
    due = %{fe: 60_000, pta: 0}

    balances = [
      B.balance(@types, due, %{fe: 60_000}, @tranches, on),
      B.balance(@types, due, %{fe: 10_000}, @tranches, on),
      B.balance(@types, due, %{}, @tranches, on)
    ]

    assert B.recovery(balances) == %{
             students: 3,
             expected: 180_000,
             expected_to_date: 72_000,
             collected: 70_000,
             rate: 38,
             rate_to_date: 97,
             behind: 2
           }

    assert B.recovery([]).rate == 0
  end

  describe "overdue_by_type/1 (Fees 2)" do
    defp bal(rows, due_to_date),
      do: %{
        by_type: Enum.map(rows, fn {id, due, paid} -> %{type_id: id, due: due, paid: paid} end),
        due_to_date: due_to_date,
        total_paid: rows |> Enum.map(&elem(&1, 2)) |> Enum.sum()
      }

    test "fills due_to_date in payment order" do
      assert B.overdue_by_type(bal([{:a, 50_000, 0}, {:b, 10_000, 0}], 24_000)) ==
               [%{type_id: :a, amount: 24_000}]
    end

    test "later types get their share once earlier ones are full" do
      assert B.overdue_by_type(bal([{:a, 20_000, 5_000}, {:b, 10_000, 0}], 24_000)) ==
               [%{type_id: :a, amount: 15_000}, %{type_id: :b, amount: 4_000}]
    end

    test "the rows add up to due_to_date minus total paid when behind" do
      for {rows, dtd} <- [
            {[{:a, 50_000, 10_000}, {:b, 10_000, 0}], 24_000},
            {[{:arr, 8_000, 0}, {:a, 50_000, 30_000}, {:b, 10_000, 0}], 54_400},
            {[{:a, 30_000, 30_000}, {:b, 30_000, 0}], 48_000}
          ] do
        b = bal(rows, dtd)
        sum = b |> B.overdue_by_type() |> Enum.map(& &1.amount) |> Enum.sum()
        assert sum == dtd - b.total_paid
      end
    end

    test "a type paid beyond its due (reduction after payment) credits later types" do
      # FE due 5 000 after a reduction but 10 000 paid; due to date 22 000 → owes 12 000.
      b = bal([{:fe, 5_000, 10_000}, {:sc, 50_000, 0}], 22_000)
      assert B.overdue_by_type(b) == [%{type_id: :sc, amount: 12_000}]
    end

    test "nothing overdue gives []" do
      assert B.overdue_by_type(bal([{:a, 50_000, 30_000}, {:b, 10_000, 0}], 24_000)) == []
    end
  end
end
