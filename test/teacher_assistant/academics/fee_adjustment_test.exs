defmodule TeacherAssistant.Academics.FeeAdjustmentTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Enrollment

  alias TeacherAssistant.Organization
  alias TeacherAssistant.Academics.FeeAdjustment
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, scope: scope} = TeacherFixtures.school_fixture()

    {:ok, year} =
      Organization.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, _student} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enrollment}] = Enrollment.list_roster(scope, cg)

    %{ws: ws, enrollment: enrollment}
  end

  defp base_attrs(ctx, overrides \\ %{}) do
    %{
      amount: 5_000,
      reason: "Bourse partielle",
      recorded_by_user_id: nil,
      enrollment_id: ctx.enrollment.id
    }
    |> Map.merge(overrides)
  end

  test "creating an adjustment persists amount/reason", ctx do
    assert {:ok, %FeeAdjustment{} = adj} =
             FeeAdjustment
             |> Ash.Changeset.for_create(:set, base_attrs(ctx))
             |> Ash.Changeset.set_tenant(ctx.ws.id)
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
      |> Ash.Changeset.set_tenant(ctx.ws.id)
      |> Ash.create(authorize?: false)

    assert {:ok, adj2} =
             FeeAdjustment
             |> Ash.Changeset.for_create(
               :set,
               base_attrs(ctx, %{amount: 8_000, reason: "Bourse totale"})
             )
             |> Ash.Changeset.set_tenant(ctx.ws.id)
             |> Ash.create(authorize?: false)

    assert adj2.id == adj1.id
    assert adj2.amount == 8_000
    assert adj2.reason == "Bourse totale"

    assert FeeAdjustment
           |> Ash.Query.filter(enrollment_id == ^ctx.enrollment.id)
           |> Ash.read!(tenant: ctx.ws.id, authorize?: false)
           |> length() == 1
  end

  test "deleting the enrollment cascades to delete its adjustments", ctx do
    {:ok, adj} =
      FeeAdjustment
      |> Ash.Changeset.for_create(:set, base_attrs(ctx))
      |> Ash.Changeset.set_tenant(ctx.ws.id)
      |> Ash.create(authorize?: false)

    :ok = Ash.destroy!(ctx.enrollment, authorize?: false)

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.get(FeeAdjustment, adj.id, tenant: ctx.ws.id, authorize?: false)
  end
end
