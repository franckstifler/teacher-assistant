defmodule TeacherAssistant.Academics.FeeAdjustmentTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.FeeAdjustment
  alias TeacherAssistant.TeacherFixtures

  setup do
    ws = TeacherFixtures.workspace_fixture()

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    {:ok, _student} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enrollment}] = Academics.list_roster(cg)

    %{ws: ws, enrollment: enrollment}
  end

  defp base_attrs(ctx, overrides \\ %{}) do
    %{
      amount: 5_000,
      reason: "Bourse partielle",
      recorded_by_user_id: nil,
      workspace_id: ctx.ws.id,
      enrollment_id: ctx.enrollment.id
    }
    |> Map.merge(overrides)
  end

  test "creating an adjustment persists amount/reason", ctx do
    assert {:ok, %FeeAdjustment{} = adj} =
             FeeAdjustment
             |> Ash.Changeset.for_create(:set, base_attrs(ctx))
             |> Ash.create(authorize?: false)

    assert adj.amount == 5_000
    assert adj.reason == "Bourse partielle"
    assert adj.enrollment_id == ctx.enrollment.id
  end

  test "the unique_adjustment identity upserts a second adjustment for the same enrollment",
       ctx do
    {:ok, adj1} =
      FeeAdjustment
      |> Ash.Changeset.for_create(:set, base_attrs(ctx, %{amount: 5_000}))
      |> Ash.create(authorize?: false)

    assert {:ok, adj2} =
             FeeAdjustment
             |> Ash.Changeset.for_create(
               :set,
               base_attrs(ctx, %{amount: 8_000, reason: "Bourse totale"})
             )
             |> Ash.create(authorize?: false)

    assert adj2.id == adj1.id
    assert adj2.amount == 8_000
    assert adj2.reason == "Bourse totale"

    assert FeeAdjustment
           |> Ash.Query.filter(enrollment_id == ^ctx.enrollment.id)
           |> Ash.read!(authorize?: false)
           |> length() == 1
  end

  test "deleting the enrollment cascades to delete its adjustments", ctx do
    {:ok, adj} =
      FeeAdjustment
      |> Ash.Changeset.for_create(:set, base_attrs(ctx))
      |> Ash.create(authorize?: false)

    :ok = Ash.destroy!(ctx.enrollment, authorize?: false)

    assert {:error, %Ash.Error.Invalid{}} = Ash.get(FeeAdjustment, adj.id, authorize?: false)
  end
end
