defmodule TeacherAssistant.Academics.TimetablesSlotsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Timetabling
  alias TeacherAssistant.Academics.TimetableSlot
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Test"
      })

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg_a} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, cg_b} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})

    {:ok, tc_a} = Curriculum.assign_teacher(scope, cg_a, head, %{subject: "Maths"})
    {:ok, tc_b} = Curriculum.assign_teacher(scope, cg_b, head, %{subject: "Maths"})

    :ok = Attendance.build_default_periods(scope)
    period = Attendance.list_periods(scope) |> Enum.find(&(&1.kind == :lesson))

    %{
      head: head,
      scope: scope,
      school: school,
      year: year,
      cg_a: cg_a,
      cg_b: cg_b,
      tc_a: tc_a,
      tc_b: tc_b,
      period: period
    }
  end

  test "place_slot creates a slot", ctx do
    %{cg_a: cg_a, tc_a: tc_a, period: period, scope: scope} = ctx

    assert {:ok, %TimetableSlot{} = slot} =
             Timetabling.place_slot(scope, cg_a, %{
               day: :monday,
               period_id: period.id,
               teaching_context_id: tc_a.id
             })

    assert slot.class_group_id == cg_a.id
    assert slot.teaching_context_id == tc_a.id
  end

  test "placing the same teacher in another class at the same cell clashes", ctx do
    %{cg_a: cg_a, cg_b: cg_b, tc_a: tc_a, tc_b: tc_b, period: period, scope: scope} = ctx

    {:ok, _slot} =
      Timetabling.place_slot(scope, cg_a, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc_a.id
      })

    assert {:error, {:teacher_clash, "6e A"}} =
             Timetabling.place_slot(scope, cg_b, %{
               day: :monday,
               period_id: period.id,
               teaching_context_id: tc_b.id
             })

    refute Enum.any?(
             list_slots_for_cell(cg_b, :monday, period.id),
             &(&1.class_group_id == cg_b.id)
           )
  end

  test "placing a different teacher/subject in the other class at the same cell succeeds", ctx do
    %{
      cg_a: cg_a,
      cg_b: cg_b,
      tc_a: tc_a,
      school: school,
      head: head,
      period: period,
      scope: scope
    } =
      ctx

    other_teacher = TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(other_teacher.email),
        roles: [:teacher]
      })

    {:ok, _member} =
      Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other_teacher}, inv.token)

    {:ok, tc_other} = Curriculum.assign_teacher(scope, cg_b, other_teacher, %{subject: "Anglais"})

    {:ok, _slot_a} =
      Timetabling.place_slot(scope, cg_a, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc_a.id
      })

    assert {:ok, %TimetableSlot{}} =
             Timetabling.place_slot(scope, cg_b, %{
               day: :monday,
               period_id: period.id,
               teaching_context_id: tc_other.id
             })
  end

  test "replacing the same cell keeps a single slot and does not self-clash", ctx do
    %{cg_a: cg_a, tc_a: tc_a, period: period, scope: scope} = ctx
    {:ok, tc_a2} = Curriculum.assign_teacher(scope, cg_a, ctx.head, %{subject: "SVT"})

    {:ok, slot1} =
      Timetabling.place_slot(scope, cg_a, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc_a.id
      })

    assert {:ok, slot2} =
             Timetabling.place_slot(scope, cg_a, %{
               day: :monday,
               period_id: period.id,
               teaching_context_id: tc_a2.id
             })

    assert slot2.id == slot1.id
    assert slot2.teaching_context_id == tc_a2.id
    assert length(list_slots_for_cell(cg_a, :monday, period.id)) == 1
  end

  test "placing a teaching_context from another class is rejected", ctx do
    %{cg_a: cg_a, tc_b: tc_b, period: period, scope: scope} = ctx

    assert {:error, :invalid} =
             Timetabling.place_slot(scope, cg_a, %{
               day: :monday,
               period_id: period.id,
               teaching_context_id: tc_b.id
             })
  end

  test "clear_slot removes the cell and is idempotent", ctx do
    %{cg_a: cg_a, tc_a: tc_a, period: period, scope: scope} = ctx

    {:ok, _slot} =
      Timetabling.place_slot(scope, cg_a, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc_a.id
      })

    assert :ok = Timetabling.clear_slot(scope, cg_a, :monday, period.id)
    assert list_slots_for_cell(cg_a, :monday, period.id) == []
    assert :ok = Timetabling.clear_slot(scope, cg_a, :monday, period.id)
  end

  defp list_slots_for_cell(cg, day, period_id) do
    require Ash.Query

    TimetableSlot
    |> Ash.Query.filter(day == ^day and period_id == ^period_id)
    |> Ash.Query.set_tenant(cg.workspace_id)
    |> Ash.read!(authorize?: false)
  end
end
