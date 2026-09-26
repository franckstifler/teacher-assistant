defmodule TeacherAssistant.Academics.SanctionEntryTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.SanctionEntry
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Test"
      })

    {:ok, year} =
      Organization.create_academic_year(school_scope(head, ws), %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    scope = school_scope(head, ws)

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, student} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enrollment}] = Enrollment.list_roster(scope, cg)

    %{
      ws: ws,
      scope: scope,
      year: year,
      cg: cg,
      student: student,
      enrollment: enrollment,
      head: head
    }
  end

  defp base_attrs(ctx, overrides \\ %{}) do
    %{
      type: :avertissement,
      date: ~D[2025-09-15],
      reason: "Bavardage répété",
      duration_days: nil,
      issued_by_user_id: ctx.head.id,
      enrollment_id: ctx.enrollment.id
    }
    |> Map.merge(overrides)
  end

  test "creating a sanction entry persists type/date/reason/duration_days/workspace_id", ctx do
    assert {:ok, %SanctionEntry{} = entry} =
             SanctionEntry
             |> Ash.Changeset.for_create(:create, base_attrs(ctx))
             |> Ash.create(scope: ctx.scope)

    assert entry.type == :avertissement
    assert entry.date == ~D[2025-09-15]
    assert entry.reason == "Bavardage répété"
    assert entry.duration_days == nil
    assert entry.workspace_id == ctx.ws.id
  end

  test "type rejects a value outside the five enum atoms", ctx do
    assert {:error, %Ash.Error.Invalid{}} =
             SanctionEntry
             |> Ash.Changeset.for_create(:create, base_attrs(ctx, %{type: :suspension}))
             |> Ash.create(scope: ctx.scope)
  end

  test "deleting the enrollment cascades to delete its sanctions", ctx do
    {:ok, entry} =
      SanctionEntry
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.create(scope: ctx.scope)

    :ok = Ash.destroy!(ctx.enrollment, scope: ctx.scope)

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.get(SanctionEntry, entry.id, scope: ctx.scope)
  end

  test "two entries of the same type for one enrollment both persist", ctx do
    {:ok, entry1} =
      SanctionEntry
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.create(scope: ctx.scope)

    {:ok, entry2} =
      SanctionEntry
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.create(scope: ctx.scope)

    assert entry1.id != entry2.id

    assert SanctionEntry
           |> Ash.Query.filter(enrollment_id == ^ctx.enrollment.id)
           |> Ash.read!(scope: ctx.scope)
           |> length() == 2
  end
end
