defmodule TeacherAssistant.Academics.FeesTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Fees
  alias TeacherAssistant.Academics.FeeAdjustment
  alias TeacherAssistant.Academics.FeeTranche
  alias TeacherAssistant.Academics.Payment
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Schools.create_school(head, %{name: "Lycée Test"})

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})

    {:ok, _student1} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    {:ok, _student2} = Academics.add_student(cg, %{full_name: "Bilal", sex: :m})

    [%{enrollment: enrollment1}, %{enrollment: enrollment2}] = Academics.list_roster(cg)

    %{
      ws: ws,
      year: year,
      cg: cg,
      head: head,
      enrollment1: enrollment1,
      enrollment2: enrollment2
    }
  end

  describe "add_tranche/2" do
    test "persists with the class's workspace_id and position 0 for the first tranche", ctx do
      assert {:ok, %FeeTranche{} = tranche} =
               Fees.add_tranche(ctx.cg, %{
                 label: "1ère tranche",
                 amount: 25_000,
                 due_date: ~D[2025-10-15]
               })

      assert tranche.workspace_id == ctx.ws.id
      assert tranche.class_group_id == ctx.cg.id
      assert tranche.position == 0
    end

    test "appends position for a second tranche", ctx do
      {:ok, _first} =
        Fees.add_tranche(ctx.cg, %{
          label: "1ère tranche",
          amount: 25_000,
          due_date: ~D[2025-10-15]
        })

      assert {:ok, %FeeTranche{} = second} =
               Fees.add_tranche(ctx.cg, %{
                 label: "2ème tranche",
                 amount: 15_000,
                 due_date: ~D[2025-12-15]
               })

      assert second.position == 1
    end

    test "rejects a negative amount", ctx do
      assert {:error, :invalid_amount} =
               Fees.add_tranche(ctx.cg, %{
                 label: "Invalide",
                 amount: -1,
                 due_date: ~D[2025-10-15]
               })
    end

    test "translates an Ash write failure (nil due_date) to a tagged error, not a raw struct",
         ctx do
      assert {:error, :tranche_failed} =
               Fees.add_tranche(ctx.cg, %{
                 label: "Sans date",
                 amount: 10_000,
                 due_date: nil
               })
    end
  end

  describe "list_tranches/1" do
    test "returns tranches ordered by position ascending", ctx do
      {:ok, first} =
        Fees.add_tranche(ctx.cg, %{
          label: "1ère tranche",
          amount: 25_000,
          due_date: ~D[2025-10-15]
        })

      {:ok, second} =
        Fees.add_tranche(ctx.cg, %{
          label: "2ème tranche",
          amount: 15_000,
          due_date: ~D[2025-12-15]
        })

      assert Fees.list_tranches(ctx.cg) |> Enum.map(& &1.id) == [first.id, second.id]
    end

    test "returns [] when the class has no tranches", ctx do
      assert Fees.list_tranches(ctx.cg) == []
    end
  end

  describe "update_tranche/2" do
    test "changes the amount", ctx do
      {:ok, tranche} =
        Fees.add_tranche(ctx.cg, %{
          label: "1ère tranche",
          amount: 25_000,
          due_date: ~D[2025-10-15]
        })

      assert {:ok, updated} = Fees.update_tranche(tranche, %{amount: 30_000})
      assert updated.amount == 30_000
    end

    test "rejects a negative amount", ctx do
      {:ok, tranche} =
        Fees.add_tranche(ctx.cg, %{
          label: "1ère tranche",
          amount: 25_000,
          due_date: ~D[2025-10-15]
        })

      assert {:error, :invalid_amount} = Fees.update_tranche(tranche, %{amount: -5})
    end

    test "ignores a position key in attrs, leaving the append-managed position untouched",
         ctx do
      {:ok, _first} =
        Fees.add_tranche(ctx.cg, %{
          label: "1ère tranche",
          amount: 25_000,
          due_date: ~D[2025-10-15]
        })

      {:ok, second} =
        Fees.add_tranche(ctx.cg, %{
          label: "2ème tranche",
          amount: 15_000,
          due_date: ~D[2025-12-15]
        })

      assert second.position == 1

      assert {:ok, updated} = Fees.update_tranche(second, %{position: 99, amount: 5_000})
      assert updated.amount == 5_000
      assert updated.position == 1
    end
  end

  describe "delete_tranche/1" do
    test "removes the row", ctx do
      {:ok, tranche} =
        Fees.add_tranche(ctx.cg, %{
          label: "1ère tranche",
          amount: 25_000,
          due_date: ~D[2025-10-15]
        })

      assert :ok = Fees.delete_tranche(tranche)
      assert Fees.list_tranches(ctx.cg) == []
    end
  end

  describe "record_payment/3" do
    test "persists with the enrollment's workspace_id", ctx do
      assert {:ok, %Payment{} = payment} =
               Fees.record_payment(
                 ctx.enrollment1,
                 %{amount: 10_000, paid_on: ~D[2025-10-01], method: :cash},
                 ctx.head.id
               )

      assert payment.workspace_id == ctx.ws.id
      assert payment.enrollment_id == ctx.enrollment1.id
      assert payment.amount == 10_000
      assert payment.method == :cash
    end

    test "rejects a zero amount", ctx do
      assert {:error, :invalid_amount} =
               Fees.record_payment(
                 ctx.enrollment1,
                 %{amount: 0, paid_on: ~D[2025-10-01], method: :cash},
                 ctx.head.id
               )
    end

    test "rejects a negative amount", ctx do
      assert {:error, :invalid_amount} =
               Fees.record_payment(
                 ctx.enrollment1,
                 %{amount: -100, paid_on: ~D[2025-10-01], method: :cash},
                 ctx.head.id
               )
    end

    test "rejects an invalid method", ctx do
      assert {:error, :invalid_method} =
               Fees.record_payment(
                 ctx.enrollment1,
                 %{amount: 10_000, paid_on: ~D[2025-10-01], method: :check},
                 ctx.head.id
               )
    end

    test "translates an Ash write failure (nil paid_on) to a tagged error, not a raw struct",
         ctx do
      assert {:error, :payment_failed} =
               Fees.record_payment(
                 ctx.enrollment1,
                 %{amount: 10_000, paid_on: nil, method: :cash},
                 ctx.head.id
               )
    end
  end

  describe "list_payments/1" do
    test "returns payments newest first by paid_on", ctx do
      {:ok, older} =
        Fees.record_payment(
          ctx.enrollment1,
          %{amount: 5_000, paid_on: ~D[2025-09-15], method: :cash},
          ctx.head.id
        )

      {:ok, newer} =
        Fees.record_payment(
          ctx.enrollment1,
          %{amount: 5_000, paid_on: ~D[2025-10-15], method: :mobile_money},
          ctx.head.id
        )

      assert Fees.list_payments(ctx.enrollment1) |> Enum.map(& &1.id) == [newer.id, older.id]
    end

    test "scopes to the given enrollment only", ctx do
      {:ok, mine} =
        Fees.record_payment(
          ctx.enrollment1,
          %{amount: 5_000, paid_on: ~D[2025-09-15], method: :cash},
          ctx.head.id
        )

      {:ok, _other} =
        Fees.record_payment(
          ctx.enrollment2,
          %{amount: 5_000, paid_on: ~D[2025-09-15], method: :cash},
          ctx.head.id
        )

      assert Fees.list_payments(ctx.enrollment1) |> Enum.map(& &1.id) == [mine.id]
    end
  end

  describe "delete_payment/1" do
    test "removes the row", ctx do
      {:ok, payment} =
        Fees.record_payment(
          ctx.enrollment1,
          %{amount: 5_000, paid_on: ~D[2025-09-15], method: :cash},
          ctx.head.id
        )

      assert :ok = Fees.delete_payment(payment)
      assert Fees.list_payments(ctx.enrollment1) == []
    end
  end

  describe "set_adjustment/3" do
    test "persists with the enrollment's workspace_id", ctx do
      assert {:ok, %FeeAdjustment{} = adjustment} =
               Fees.set_adjustment(
                 ctx.enrollment1,
                 %{amount: 5_000, reason: "Bourse"},
                 ctx.head.id
               )

      assert adjustment.workspace_id == ctx.ws.id
      assert adjustment.enrollment_id == ctx.enrollment1.id
      assert adjustment.amount == 5_000
    end

    test "re-setting upserts: one row, latest value replaces", ctx do
      {:ok, _} =
        Fees.set_adjustment(ctx.enrollment1, %{amount: 5_000, reason: "Bourse"}, ctx.head.id)

      assert {:ok, updated} =
               Fees.set_adjustment(
                 ctx.enrollment1,
                 %{amount: 8_000, reason: "Bourse+"},
                 ctx.head.id
               )

      assert updated.amount == 8_000

      all =
        FeeAdjustment
        |> Ash.Query.filter(enrollment_id == ^ctx.enrollment1.id)
        |> Ash.read!(authorize?: false)

      assert length(all) == 1
      assert hd(all).amount == 8_000
    end

    test "rejects a negative amount", ctx do
      assert {:error, :invalid_amount} =
               Fees.set_adjustment(ctx.enrollment1, %{amount: -1, reason: "x"}, ctx.head.id)
    end
  end

  describe "clear_adjustment/1" do
    test "deletes the adjustment for the enrollment", ctx do
      {:ok, _} =
        Fees.set_adjustment(ctx.enrollment1, %{amount: 5_000, reason: "Bourse"}, ctx.head.id)

      assert {:ok, 1} = Fees.clear_adjustment(ctx.enrollment1)

      assert FeeAdjustment
             |> Ash.Query.filter(enrollment_id == ^ctx.enrollment1.id)
             |> Ash.read!(authorize?: false) == []
    end

    test "returns {:ok, 0} when no adjustment exists", ctx do
      assert {:ok, 0} = Fees.clear_adjustment(ctx.enrollment1)
    end
  end

  describe "student_balance/2" do
    test "composes tranches + partial payment into :behind with the right shortfall", ctx do
      {:ok, _} =
        Fees.add_tranche(ctx.cg, %{label: "1ère", amount: 10_000, due_date: ~D[2025-09-15]})

      {:ok, _} =
        Fees.add_tranche(ctx.cg, %{label: "2ème", amount: 20_000, due_date: ~D[2025-12-15]})

      {:ok, _} =
        Fees.record_payment(
          ctx.enrollment1,
          %{amount: 4_000, paid_on: ~D[2025-09-20], method: :cash},
          ctx.head.id
        )

      balance = Fees.student_balance(ctx.enrollment1, ~D[2025-10-01])

      assert balance.total_due == 30_000
      assert balance.due_to_date == 10_000
      assert balance.total_paid == 4_000
      assert balance.balance == 26_000
      assert balance.status == :behind
    end

    test "paying up to due_to_date reaches :paid_up once total_due is covered", ctx do
      {:ok, _} =
        Fees.add_tranche(ctx.cg, %{label: "1ère", amount: 10_000, due_date: ~D[2025-09-15]})

      {:ok, _} =
        Fees.record_payment(
          ctx.enrollment1,
          %{amount: 10_000, paid_on: ~D[2025-09-20], method: :cash},
          ctx.head.id
        )

      balance = Fees.student_balance(ctx.enrollment1, ~D[2025-10-01])

      assert balance.total_due == 10_000
      assert balance.total_paid == 10_000
      assert balance.balance == 0
      assert balance.status == :paid_up
    end

    test "adjustment amount defaults to 0 when none set", ctx do
      {:ok, _} =
        Fees.add_tranche(ctx.cg, %{label: "1ère", amount: 10_000, due_date: ~D[2025-09-15]})

      balance = Fees.student_balance(ctx.enrollment1, ~D[2025-10-01])

      assert balance.total_due == 10_000
    end

    test "reflects the adjustment amount, reducing total_due", ctx do
      {:ok, _} =
        Fees.add_tranche(ctx.cg, %{label: "1ère", amount: 10_000, due_date: ~D[2025-09-15]})

      {:ok, _} =
        Fees.set_adjustment(ctx.enrollment1, %{amount: 4_000, reason: "Bourse"}, ctx.head.id)

      balance = Fees.student_balance(ctx.enrollment1, ~D[2025-10-01])

      assert balance.total_due == 6_000
    end

    test "accepts a bare enrollment id", ctx do
      {:ok, _} =
        Fees.add_tranche(ctx.cg, %{label: "1ère", amount: 10_000, due_date: ~D[2025-09-15]})

      balance = Fees.student_balance(ctx.enrollment1.id, ~D[2025-10-01])

      assert balance.total_due == 10_000
    end
  end

  describe "class_balances/2" do
    test "returns every roster enrollment in one pass; unpaid student shows schedule due/status",
         ctx do
      {:ok, _} =
        Fees.add_tranche(ctx.cg, %{label: "1ère", amount: 10_000, due_date: ~D[2025-09-15]})

      {:ok, _} =
        Fees.record_payment(
          ctx.enrollment1,
          %{amount: 10_000, paid_on: ~D[2025-09-20], method: :cash},
          ctx.head.id
        )

      result = Fees.class_balances(ctx.cg, ~D[2025-10-01])

      assert map_size(result) == 2

      b1 = result[ctx.enrollment1.id]
      assert b1.total_paid == 10_000
      assert b1.status == :paid_up

      b2 = result[ctx.enrollment2.id]
      assert b2.total_due == 10_000
      assert b2.total_paid == 0
      assert b2.due_to_date == 10_000
      assert b2.status == :behind
    end

    test "reflects an adjustment for the affected student only", ctx do
      {:ok, _} =
        Fees.add_tranche(ctx.cg, %{label: "1ère", amount: 10_000, due_date: ~D[2025-09-15]})

      {:ok, _} =
        Fees.set_adjustment(ctx.enrollment1, %{amount: 10_000, reason: "Bourse"}, ctx.head.id)

      result = Fees.class_balances(ctx.cg, ~D[2025-10-01])

      assert result[ctx.enrollment1.id].total_due == 0
      assert result[ctx.enrollment1.id].status == :paid_up

      assert result[ctx.enrollment2.id].total_due == 10_000
    end
  end
end
