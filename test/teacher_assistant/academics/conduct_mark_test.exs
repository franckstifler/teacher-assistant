defmodule TeacherAssistant.Academics.ConductMarkTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.ConductMark
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

    Academics.build_default_calendar(year)
    seq = Academics.list_sequences(year) |> List.first()

    {:ok, cg} = Academics.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    {:ok, _student} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enrollment}] = Academics.list_roster(cg)

    %{ws: ws, seq: seq, enrollment: enrollment}
  end

  defp base_attrs(ctx, overrides \\ %{}) do
    %{
      value: Decimal.new(18),
      recorded_by_user_id: nil,
      workspace_id: ctx.ws.id,
      enrollment_id: ctx.enrollment.id,
      sequence_id: ctx.seq.id
    }
    |> Map.merge(overrides)
  end

  test "creating a mark persists value/sequence/enrollment", ctx do
    assert {:ok, %ConductMark{} = mark} =
             ConductMark
             |> Ash.Changeset.for_create(:set, base_attrs(ctx))
             |> Ash.create(authorize?: false)

    assert Decimal.equal?(mark.value, Decimal.new(18))
    assert mark.sequence_id == ctx.seq.id
    assert mark.enrollment_id == ctx.enrollment.id
  end

  test "the unique_conduct_mark identity upserts a second mark for the same (enrollment, sequence)",
       ctx do
    {:ok, mark1} =
      ConductMark
      |> Ash.Changeset.for_create(:set, base_attrs(ctx, %{value: Decimal.new(18)}))
      |> Ash.create(authorize?: false)

    assert {:ok, mark2} =
             ConductMark
             |> Ash.Changeset.for_create(:set, base_attrs(ctx, %{value: Decimal.new(12)}))
             |> Ash.create(authorize?: false)

    assert mark2.id == mark1.id
    assert Decimal.equal?(mark2.value, Decimal.new(12))

    assert ConductMark
           |> Ash.Query.filter(enrollment_id == ^ctx.enrollment.id)
           |> Ash.read!(authorize?: false)
           |> length() == 1
  end

  test "deleting the enrollment cascades to delete its marks", ctx do
    {:ok, mark} =
      ConductMark
      |> Ash.Changeset.for_create(:set, base_attrs(ctx))
      |> Ash.create(authorize?: false)

    :ok = Ash.destroy!(ctx.enrollment, authorize?: false)

    assert {:error, %Ash.Error.Invalid{}} = Ash.get(ConductMark, mark.id, authorize?: false)
  end

  test "deleting the sequence cascades to delete its marks", ctx do
    {:ok, mark} =
      ConductMark
      |> Ash.Changeset.for_create(:set, base_attrs(ctx))
      |> Ash.create(authorize?: false)

    :ok = Ash.destroy!(ctx.seq, authorize?: false)

    assert {:error, %Ash.Error.Invalid{}} = Ash.get(ConductMark, mark.id, authorize?: false)
  end
end
