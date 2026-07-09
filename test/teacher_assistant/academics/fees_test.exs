defmodule TeacherAssistant.Academics.FeesTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Fees
  alias TeacherAssistant.Academics.FeeTranche
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

    %{
      ws: ws,
      year: year,
      cg: cg,
      head: head
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
end
