defmodule TeacherAssistant.Academics.TimetablesSlotsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Academics.TimetableSlot
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, school} = Schools.create_school(head, %{name: "Lycée Test"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg_a} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, cg_b} = Academics.create_class_group(school, year, %{label: "6e B", level: "6ème"})

    {:ok, tc_a} = Assignments.assign(cg_a, head, %{subject: "Maths"})
    {:ok, tc_b} = Assignments.assign(cg_b, head, %{subject: "Maths"})

    :ok = Timetables.build_default_periods(school)
    period = Timetables.list_periods(school) |> Enum.find(&(&1.kind == :lesson))

    %{
      head: head,
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
    %{cg_a: cg_a, tc_a: tc_a, period: period} = ctx

    assert {:ok, %TimetableSlot{} = slot} =
             Timetables.place_slot(cg_a, %{
               day: :monday,
               period_id: period.id,
               teaching_context_id: tc_a.id
             })

    assert slot.class_group_id == cg_a.id
    assert slot.teaching_context_id == tc_a.id
  end

  test "placing the same teacher in another class at the same cell clashes", ctx do
    %{cg_a: cg_a, cg_b: cg_b, tc_a: tc_a, tc_b: tc_b, period: period} = ctx

    {:ok, _slot} =
      Timetables.place_slot(cg_a, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc_a.id
      })

    assert {:error, {:teacher_clash, "6e A"}} =
             Timetables.place_slot(cg_b, %{
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
    %{cg_a: cg_a, cg_b: cg_b, tc_a: tc_a, school: school, head: head, period: period} = ctx
    other_teacher = TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{
        email: to_string(other_teacher.email),
        roles: [:teacher]
      })

    {:ok, _member} = Schools.accept_invitation(inv.token, other_teacher)

    {:ok, tc_other} = Assignments.assign(cg_b, other_teacher, %{subject: "Anglais"})

    {:ok, _slot_a} =
      Timetables.place_slot(cg_a, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc_a.id
      })

    assert {:ok, %TimetableSlot{}} =
             Timetables.place_slot(cg_b, %{
               day: :monday,
               period_id: period.id,
               teaching_context_id: tc_other.id
             })
  end

  test "replacing the same cell keeps a single slot and does not self-clash", ctx do
    %{cg_a: cg_a, tc_a: tc_a, period: period} = ctx
    {:ok, tc_a2} = Assignments.assign(cg_a, ctx.head, %{subject: "SVT"})

    {:ok, slot1} =
      Timetables.place_slot(cg_a, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc_a.id
      })

    assert {:ok, slot2} =
             Timetables.place_slot(cg_a, %{
               day: :monday,
               period_id: period.id,
               teaching_context_id: tc_a2.id
             })

    assert slot2.id == slot1.id
    assert slot2.teaching_context_id == tc_a2.id
    assert length(list_slots_for_cell(cg_a, :monday, period.id)) == 1
  end

  test "placing a teaching_context from another class is rejected", ctx do
    %{cg_a: cg_a, tc_b: tc_b, period: period} = ctx

    assert {:error, :invalid} =
             Timetables.place_slot(cg_a, %{
               day: :monday,
               period_id: period.id,
               teaching_context_id: tc_b.id
             })
  end

  test "clear_slot removes the cell and is idempotent", ctx do
    %{cg_a: cg_a, tc_a: tc_a, period: period} = ctx

    {:ok, _slot} =
      Timetables.place_slot(cg_a, %{
        day: :monday,
        period_id: period.id,
        teaching_context_id: tc_a.id
      })

    assert :ok = Timetables.clear_slot(cg_a, :monday, period.id)
    assert list_slots_for_cell(cg_a, :monday, period.id) == []
    assert :ok = Timetables.clear_slot(cg_a, :monday, period.id)
  end

  defp list_slots_for_cell(cg, day, period_id) do
    require Ash.Query

    TimetableSlot
    |> Ash.Query.filter(
      workspace_id == ^cg.workspace_id and day == ^day and period_id == ^period_id
    )
    |> Ash.read!(authorize?: false)
  end
end
