defmodule TeacherAssistant.Academics.PaymentTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Academics
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
    {:ok, student} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enrollment}] = Academics.list_roster(cg)

    %{
      ws: ws,
      year: year,
      cg: cg,
      student: student,
      enrollment: enrollment,
      head: head
    }
  end

  defp base_attrs(ctx, overrides \\ %{}) do
    %{
      amount: 25_000,
      paid_on: ~D[2025-09-20],
      method: :cash,
      reference: "REC-0001",
      note: "Première tranche",
      recorded_by_user_id: ctx.head.id,
      workspace_id: ctx.ws.id,
      enrollment_id: ctx.enrollment.id
    }
    |> Map.merge(overrides)
  end

  test "creating a payment persists amount/paid_on/method/reference/workspace_id", ctx do
    assert {:ok, %Payment{} = payment} =
             Payment
             |> Ash.Changeset.for_create(:create, base_attrs(ctx))
             |> Ash.create(authorize?: false)

    assert payment.amount == 25_000
    assert payment.paid_on == ~D[2025-09-20]
    assert payment.method == :cash
    assert payment.reference == "REC-0001"
    assert payment.workspace_id == ctx.ws.id
  end

  test "method rejects a value outside the four enum atoms", ctx do
    assert {:error, %Ash.Error.Invalid{}} =
             Payment
             |> Ash.Changeset.for_create(:create, base_attrs(ctx, %{method: :cheque}))
             |> Ash.create(authorize?: false)
  end

  test "deleting the enrollment cascades to delete its payments", ctx do
    {:ok, payment} =
      Payment
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.create(authorize?: false)

    :ok = Ash.destroy!(ctx.enrollment, authorize?: false)

    assert {:error, %Ash.Error.Invalid{}} = Ash.get(Payment, payment.id, authorize?: false)
  end

  test "two payments for one enrollment both persist", ctx do
    {:ok, payment1} =
      Payment
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.create(authorize?: false)

    {:ok, payment2} =
      Payment
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.create(authorize?: false)

    assert payment1.id != payment2.id

    assert Payment
           |> Ash.Query.filter(enrollment_id == ^ctx.enrollment.id)
           |> Ash.read!(authorize?: false)
           |> length() == 2
  end
end
