defmodule TeacherAssistant.CompositeFkTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.Academics.{AttendanceEntry, CombinedCourse, TeachingContext}
  alias TeacherAssistant.{Attendance, Enrollment}

  setup do
    a = setup_complete_school_fixture()
    b = setup_complete_school_fixture()
    [cg_a | _] = Enrollment.list_class_groups(a.scope, a.year)

    {:ok, %{enrollment: e_a}} =
      Enrollment.enroll_new(a.scope, cg_a, %{full_name: "Awa A", sex: :f})

    [period_a | _] = Attendance.list_periods(a.scope)
    [period_b | _] = Attendance.list_periods(b.scope)
    tc_b = assigned_context_fixture(b.scope, b.year)
    %{a: a, e_a: e_a, period_a: period_a, period_b: period_b, tc_b: tc_b}
  end

  defp entry(ctx, attrs) do
    AttendanceEntry
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(%{date: ~D[2025-09-15], status: :absent, enrollment_id: ctx.e_a.id}, attrs)
    )
    |> Ash.Changeset.set_tenant(ctx.a.workspace.id)
    |> Ash.create()
  end

  test "a non-null reference to another school's row is rejected by the database", ctx do
    assert {:ok, _} = entry(ctx, %{period_id: ctx.period_a.id})
    assert {:error, %Ash.Error.Invalid{}} = entry(ctx, %{period_id: ctx.period_b.id})
  end

  test "a nullable reference accepts nil and rejects another school's row", ctx do
    assert {:ok, _} = entry(ctx, %{period_id: ctx.period_a.id, teaching_context_id: nil})

    assert {:error, %Ash.Error.Invalid{}} =
             entry(ctx, %{period_id: ctx.period_a.id, teaching_context_id: ctx.tc_b.id})
  end

  test "deleting a combined course nulls only combined_course_id on its contexts", ctx do
    tc1 = assigned_context_fixture(ctx.a.scope, ctx.a.year, %{subject: "Physique"})
    tenant = ctx.a.workspace.id

    {:ok, course} =
      CombinedCourse
      |> Ash.Changeset.for_create(:create, %{
        subject: "Physique",
        label: "Physique commune",
        academic_year_id: ctx.a.year.id,
        teacher_user_id: tc1.teacher_user_id
      })
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.create()

    {:ok, _} =
      tc1
      |> Ash.Changeset.for_update(:update, %{combined_course_id: course.id})
      |> Ash.Changeset.set_tenant(tenant)
      |> Ash.update()

    :ok = Ash.destroy(course, tenant: tenant)

    reloaded = Ash.get!(TeachingContext, tc1.id, tenant: tenant)
    assert reloaded.combined_course_id == nil
    assert reloaded.workspace_id == tenant
  end
end
