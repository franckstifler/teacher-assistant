defmodule TeacherAssistant.Academics.AttendanceEntryTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Academics.AttendanceEntry
  alias TeacherAssistant.Attendance
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

    {:ok, cg} = Enrollment.create_class_group(ws, year, %{label: "6e A", level: "6ème"})
    {:ok, tc} = Curriculum.assign_teacher(cg, head, %{subject: "Maths"})
    {:ok, student} = Enrollment.add_student(cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: enrollment}] = Enrollment.list_roster(cg)

    :ok = Attendance.build_default_periods(ws)
    period = Attendance.list_periods(ws) |> Enum.find(&(&1.kind == :lesson))

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
      recorded_by_user_id: nil
    }
    |> Map.merge(overrides)
  end

  test "creating an entry persists status/date/justified", ctx do
    assert {:ok, %AttendanceEntry{} = entry} =
             AttendanceEntry
             |> Ash.Changeset.for_create(:create, base_attrs(ctx))
             |> Ash.Changeset.set_tenant(ctx.ws.id)
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
      |> Ash.Changeset.set_tenant(ctx.ws.id)
      |> Ash.create(authorize?: false)

    assert {:ok, entry2} =
             AttendanceEntry
             |> Ash.Changeset.for_create(:record, base_attrs(ctx, %{status: :absent}))
             |> Ash.Changeset.set_tenant(ctx.ws.id)
             |> Ash.create(authorize?: false)

    assert entry2.id == entry1.id
    assert entry2.status == :absent

    assert AttendanceEntry
           |> Ash.Query.filter(enrollment_id == ^ctx.enrollment.id)
           |> Ash.read!(tenant: ctx.ws.id, authorize?: false)
           |> length() == 1
  end

  test "deleting the enrollment cascades to delete its entries", ctx do
    {:ok, entry} =
      AttendanceEntry
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.Changeset.set_tenant(ctx.ws.id)
      |> Ash.create(authorize?: false)

    :ok = Ash.destroy!(ctx.enrollment, tenant: ctx.ws.id, authorize?: false)

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.get(AttendanceEntry, entry.id, tenant: ctx.ws.id, authorize?: false)
  end

  test "deleting the period cascades to delete its entries", ctx do
    {:ok, entry} =
      AttendanceEntry
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.Changeset.set_tenant(ctx.ws.id)
      |> Ash.create(authorize?: false)

    :ok = Ash.destroy!(ctx.period, tenant: ctx.ws.id, authorize?: false)

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.get(AttendanceEntry, entry.id, tenant: ctx.ws.id, authorize?: false)
  end

  test "justified defaults to false", ctx do
    {:ok, entry} =
      AttendanceEntry
      |> Ash.Changeset.for_create(:create, base_attrs(ctx))
      |> Ash.Changeset.set_tenant(ctx.ws.id)
      |> Ash.create(authorize?: false)

    assert entry.justified == false
  end

  test "status rejects a value outside [:present, :absent, :late]", ctx do
    assert {:error, %Ash.Error.Invalid{}} =
             AttendanceEntry
             |> Ash.Changeset.for_create(:create, base_attrs(ctx, %{status: :tardy}))
             |> Ash.Changeset.set_tenant(ctx.ws.id)
             |> Ash.create(authorize?: false)
  end
end
