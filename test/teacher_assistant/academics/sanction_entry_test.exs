defmodule TeacherAssistant.Academics.SanctionEntryTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.SanctionEntry
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
      type: :avertissement,
      date: ~D[2025-09-15],
      reason: "Bavardage répété",
      duration_days: nil,
      issued_by_user_id: ctx.head.id,
      workspace_id: ctx.ws.id,
      enrollment_id: ctx.enrollment.id
    }
    |> Map.merge(overrides)
  end

  test "creating a sanction entry persists type/date/reason/duration_days/workspace_id", ctx do
    assert {:ok, %SanctionEntry{} = entry} =
             SanctionEntry
             |> Ash.Changeset.for_create(:create, base_attrs(ctx))
             |> Ash.create(authorize?: false)

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
             |> Ash.create(authorize?: false)
  end

  test "deleting the enrollment cascades to delete its sanctions", ctx do
    {:ok, entry} =
      SanctionEntry
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.create(authorize?: false)

    :ok = Ash.destroy!(ctx.enrollment, authorize?: false)

    assert {:error, %Ash.Error.Invalid{}} = Ash.get(SanctionEntry, entry.id, authorize?: false)
  end

  test "two entries of the same type for one enrollment both persist", ctx do
    {:ok, entry1} =
      SanctionEntry
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.create(authorize?: false)

    {:ok, entry2} =
      SanctionEntry
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.create(authorize?: false)

    assert entry1.id != entry2.id

    assert SanctionEntry
           |> Ash.Query.filter(enrollment_id == ^ctx.enrollment.id)
           |> Ash.read!(authorize?: false)
           |> length() == 2
  end
end
