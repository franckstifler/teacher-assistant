defmodule TeacherAssistant.Academics.TypedAbsenceSettingTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Enrollment, Organization, Scope, TeacherFixtures}

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "L"})

    scope = school_scope(head, ws)
    :ok = TeacherFixtures.verify_school!(scope)
    scope = school_scope(head, ws)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    scope = %{scope | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    %{scope: scope, ws: ws, year: year, cg: cg}
  end

  test "new classes default to roll call", %{cg: cg} do
    assert cg.absence_hours_source == :roll_call
  end

  test "a conduct manager sets it", %{scope: scope, cg: cg} do
    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})

    assert {:ok, %{absence_hours_source: :typed_per_term}} =
             Enrollment.set_absence_hours_source(sg, cg, :typed_per_term)
  end

  test "a teacher, even form master, cannot set it", %{scope: scope, cg: cg} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    {:ok, cg} = Enrollment.set_form_master(scope, cg, teacher.current_user.id)

    assert {:error, %Ash.Error.Forbidden{}} =
             Enrollment.set_absence_hours_source(teacher, cg, :typed_per_term)
  end

  test "set_absence_hours_source_all sets every class of the year", ctx do
    {:ok, _} = Enrollment.create_class_group(ctx.scope, ctx.year, %{label: "6e B", level: "6ème"})

    assert :ok = Attendance.set_absence_hours_source_all(ctx.scope, ctx.year, :typed_per_sequence)

    assert ctx.scope
           |> Enrollment.list_class_groups(ctx.year)
           |> Enum.all?(&(&1.absence_hours_source == :typed_per_sequence))
  end

  test "without the appel module roll_call reads as typed_per_sequence", ctx do
    op = %Scope{current_user: TeacherFixtures.admin_user_fixture()}

    {:ok, ws} = Organization.set_modules(op, ctx.ws, [:notes, :appel, :discipline])

    assert Attendance.effective_absence_source(%{ctx.scope | current_workspace: ws}, ctx.cg) ==
             :roll_call

    {:ok, ws} = Organization.set_modules(op, ctx.ws, [:notes, :discipline])

    assert Attendance.effective_absence_source(%{ctx.scope | current_workspace: ws}, ctx.cg) ==
             :typed_per_sequence
  end
end
