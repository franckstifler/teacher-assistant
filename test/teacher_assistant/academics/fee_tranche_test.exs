defmodule TeacherAssistant.Academics.FeeTrancheTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.FeeTranche
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Organization.create_school(head, %{name: "Lycée Test"})

    {:ok, year} =
      Organization.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} =
      Enrollment.create_class_group(school_scope(head, ws), year, %{label: "6e A", level: "6ème"})

    %{
      ws: ws,
      year: year,
      cg: cg,
      head: head
    }
  end

  defp base_attrs(ctx, overrides \\ %{}) do
    %{
      label: "1ère tranche",
      amount: 25_000,
      due_date: ~D[2025-10-15],
      position: 1,
      class_group_id: ctx.cg.id
    }
    |> Map.merge(overrides)
  end

  test "creating a fee tranche persists label/amount/due_date/position/workspace_id", ctx do
    assert {:ok, %FeeTranche{} = tranche} =
             FeeTranche
             |> Ash.Changeset.for_create(:create, base_attrs(ctx))
             |> Ash.Changeset.set_tenant(ctx.ws.id)
             |> Ash.create(authorize?: false)

    assert tranche.label == "1ère tranche"
    assert tranche.amount == 25_000
    assert tranche.due_date == ~D[2025-10-15]
    assert tranche.position == 1
    assert tranche.workspace_id == ctx.ws.id
  end

  test "amount accepts 0", ctx do
    assert {:ok, %FeeTranche{} = tranche} =
             FeeTranche
             |> Ash.Changeset.for_create(:create, base_attrs(ctx, %{amount: 0}))
             |> Ash.Changeset.set_tenant(ctx.ws.id)
             |> Ash.create(authorize?: false)

    assert tranche.amount == 0
  end

  test "amount accepts a large integer", ctx do
    assert {:ok, %FeeTranche{} = tranche} =
             FeeTranche
             |> Ash.Changeset.for_create(:create, base_attrs(ctx, %{amount: 1_000_000_000}))
             |> Ash.Changeset.set_tenant(ctx.ws.id)
             |> Ash.create(authorize?: false)

    assert tranche.amount == 1_000_000_000
  end

  test "deleting the class group cascades to delete its tranches", ctx do
    {:ok, tranche} =
      FeeTranche
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.Changeset.set_tenant(ctx.ws.id)
      |> Ash.create(authorize?: false)

    :ok = Ash.destroy!(ctx.cg, authorize?: false)

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.get(FeeTranche, tranche.id, tenant: ctx.ws.id, authorize?: false)
  end
end
