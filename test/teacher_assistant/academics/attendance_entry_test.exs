defmodule TeacherAssistant.Academics.AttendanceEntryTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.AttendanceEntry
  alias TeacherAssistant.Academics.Timetables
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
    {:ok, tc} = Assignments.assign(cg, head, %{subject: "Maths"})
    {:ok, student} = Academics.add_student(cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enrollment}] = Academics.list_roster(cg)

    :ok = Timetables.build_default_periods(ws)
    period = Timetables.list_periods(ws) |> Enum.find(&(&1.kind == :lesson))

    %{
      ws: ws,
      year: year,
      cg: cg,
      tc: tc,
      student: student,
      enrollment: enrollment,
      period: period
    }
  end

  defp base_attrs(ctx, overrides \\ %{}) do
    %{
      date: ~D[2025-09-15],
      status: :present,
      enrollment_id: ctx.enrollment.id,
      period_id: ctx.period.id,
      teaching_context_id: ctx.tc.id,
      recorded_by_user_id: nil,
      workspace_id: ctx.ws.id
    }
    |> Map.merge(overrides)
  end

  test "creating an entry persists status/date/justified", ctx do
    assert {:ok, %AttendanceEntry{} = entry} =
             AttendanceEntry
             |> Ash.Changeset.for_create(:create, base_attrs(ctx))
             |> Ash.create(authorize?: false)

    assert entry.status == :present
    assert entry.date == ~D[2025-09-15]
    assert entry.justified == false
  end

  test "the unique_mark identity upserts a second entry for the same (enrollment, date, period)",
       ctx do
    {:ok, entry1} =
      AttendanceEntry
      |> Ash.Changeset.for_create(:record, base_attrs(ctx, %{status: :present}))
      |> Ash.create(authorize?: false)

    assert {:ok, entry2} =
             AttendanceEntry
             |> Ash.Changeset.for_create(:record, base_attrs(ctx, %{status: :absent}))
             |> Ash.create(authorize?: false)

    assert entry2.id == entry1.id
    assert entry2.status == :absent

    assert AttendanceEntry
           |> Ash.Query.filter(enrollment_id == ^ctx.enrollment.id)
           |> Ash.read!(authorize?: false)
           |> length() == 1
  end

  test "deleting the enrollment cascades to delete its entries", ctx do
    {:ok, entry} =
      AttendanceEntry
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.create(authorize?: false)

    :ok = Ash.destroy!(ctx.enrollment, authorize?: false)

    assert {:error, %Ash.Error.Invalid{}} = Ash.get(AttendanceEntry, entry.id, authorize?: false)
  end

  test "deleting the period cascades to delete its entries", ctx do
    {:ok, entry} =
      AttendanceEntry
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.create(authorize?: false)

    :ok = Ash.destroy!(ctx.period, authorize?: false)

    assert {:error, %Ash.Error.Invalid{}} = Ash.get(AttendanceEntry, entry.id, authorize?: false)
  end

  test "justified defaults to false", ctx do
    {:ok, entry} =
      AttendanceEntry
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.create(authorize?: false)

    assert entry.justified == false
  end

  test "status rejects a value outside [:present, :absent, :late]", ctx do
    assert {:error, %Ash.Error.Invalid{}} =
             AttendanceEntry
             |> Ash.Changeset.for_create(:create, base_attrs(ctx, %{status: :tardy}))
             |> Ash.create(authorize?: false)
  end
end
