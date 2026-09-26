defmodule TeacherAssistant.Academics.ConductMarkTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Enrollment

  alias TeacherAssistant.Organization
  alias TeacherAssistant.Academics.ConductMark
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{workspace: ws, scope: scope} = TeacherFixtures.school_fixture()

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    Organization.build_default_calendar(scope, year)
    seq = Organization.list_sequences(scope, year) |> List.first()

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, _student} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enrollment}] = Enrollment.list_roster(scope, cg)

    %{ws: ws, scope: scope, seq: seq, enrollment: enrollment}
  end

  defp base_attrs(ctx, overrides \\ %{}) do
    %{
      value: Decimal.new(18),
      recorded_by_user_id: nil,
      enrollment_id: ctx.enrollment.id,
      sequence_id: ctx.seq.id
    }
    |> Map.merge(overrides)
  end

  test "creating a mark persists value/sequence/enrollment", ctx do
    assert {:ok, %ConductMark{} = mark} =
             ConductMark
             |> Ash.Changeset.for_create(:set, base_attrs(ctx))
             |> Ash.create(scope: ctx.scope)

    assert Decimal.equal?(mark.value, Decimal.new(18))
    assert mark.sequence_id == ctx.seq.id
    assert mark.enrollment_id == ctx.enrollment.id
  end

  test "the unique_conduct_mark identity upserts a second mark for the same (enrollment, sequence)",
       ctx do
    {:ok, mark1} =
      ConductMark
      |> Ash.Changeset.for_create(:set, base_attrs(ctx, %{value: Decimal.new(18)}))
      |> Ash.create(scope: ctx.scope)

    assert {:ok, mark2} =
             ConductMark
             |> Ash.Changeset.for_create(:set, base_attrs(ctx, %{value: Decimal.new(12)}))
             |> Ash.create(scope: ctx.scope)

    assert mark2.id == mark1.id
    assert Decimal.equal?(mark2.value, Decimal.new(12))

    assert ConductMark
           |> Ash.Query.filter(enrollment_id == ^ctx.enrollment.id)
           |> Ash.read!(scope: ctx.scope)
           |> length() == 1
  end

  test "deleting the enrollment cascades to delete its marks", ctx do
    {:ok, mark} =
      ConductMark
      |> Ash.Changeset.for_create(:set, base_attrs(ctx))
      |> Ash.create(scope: ctx.scope)

    :ok = Ash.destroy!(ctx.enrollment, scope: ctx.scope)

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.get(ConductMark, mark.id, scope: ctx.scope)
  end

  test "deleting the sequence cascades to delete its marks", ctx do
    {:ok, mark} =
      ConductMark
      |> Ash.Changeset.for_create(:set, base_attrs(ctx))
      |> Ash.create(scope: ctx.scope)

    :ok = Ash.destroy!(ctx.seq, scope: ctx.scope)

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.get(ConductMark, mark.id, scope: ctx.scope)
  end
end
