defmodule TeacherAssistant.Academics.TimetablesCombinedTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

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

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Combiné"
      })

    scope = school_scope(head, ws)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, maco} = Enrollment.create_class_group(scope, year, %{label: "1ère MACO", level: "1ère"})
    {:ok, menu} = Enrollment.create_class_group(scope, year, %{label: "1ère MENU", level: "1ère"})

    {:ok, unrelated} =
      Enrollment.create_class_group(scope, year, %{label: "1ère C", level: "1ère"})

    {:ok, tc_maco} = Curriculum.assign_teacher(scope, maco, head, %{subject: "Maths"})
    {:ok, tc_menu} = Curriculum.assign_teacher(scope, menu, head, %{subject: "Maths"})

    {:ok, course} = Curriculum.combine_course(scope, [tc_maco, tc_menu])

    :ok = Attendance.build_default_periods(scope)
    period = Attendance.list_periods(scope) |> Enum.find(&(&1.kind == :lesson))

    %{
      head: head,
      scope: scope,
      ws: ws,
      year: year,
      course: course,
      maco: maco,
      menu: menu,
      unrelated: unrelated,
      tc_maco: tc_maco,
      tc_menu: tc_menu,
      period: period
    }
  end

  test "place_combined_slot creates one slot per member class without tripping the teacher clash guard",
       ctx do
    assert {:ok, slots} =
             Timetabling.place_combined_slot(ctx.scope, ctx.course, :monday, ctx.period.id)

    assert length(slots) == 2
    class_group_ids = Enum.map(slots, & &1.class_group_id) |> Enum.sort()
    assert class_group_ids == Enum.sort([ctx.maco.id, ctx.menu.id])

    maco_slot = Enum.find(slots, &(&1.class_group_id == ctx.maco.id))
    menu_slot = Enum.find(slots, &(&1.class_group_id == ctx.menu.id))

    assert maco_slot.teaching_context_id == ctx.tc_maco.id
    assert menu_slot.teaching_context_id == ctx.tc_menu.id

    assert length(list_slots_for_cell(ctx.scope, :monday, ctx.period.id)) == 2
  end

  test "clear_combined_slot removes both member slots and is idempotent", ctx do
    {:ok, _slots} = Timetabling.place_combined_slot(ctx.scope, ctx.course, :monday, ctx.period.id)

    assert :ok = Timetabling.clear_combined_slot(ctx.scope, ctx.course, :monday, ctx.period.id)
    assert list_slots_for_cell(ctx.scope, :monday, ctx.period.id) == []
    assert :ok = Timetabling.clear_combined_slot(ctx.scope, ctx.course, :monday, ctx.period.id)
  end

  test "a genuine clash between an unrelated class and the combined course's teacher is still rejected",
       ctx do
    {:ok, tc_unrelated} =
      Curriculum.assign_teacher(ctx.scope, ctx.unrelated, ctx.head, %{subject: "Physique"})

    {:ok, _slot} =
      Timetabling.place_slot(ctx.scope, ctx.unrelated, %{
        day: :monday,
        period_id: ctx.period.id,
        teaching_context_id: tc_unrelated.id
      })

    assert {:error, {:teacher_clash, "1ère C"}} =
             Timetabling.place_combined_slot(ctx.scope, ctx.course, :monday, ctx.period.id)

    assert list_slots_for_cell(ctx.scope, :monday, ctx.period.id)
           |> Enum.reject(&(&1.class_group_id == ctx.unrelated.id)) == []
  end

  test "a genuine clash between two unrelated ordinary classes is still rejected", ctx do
    other_teacher = TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(ctx.head, ctx.ws), %{
        email: to_string(other_teacher.email),
        roles: [:teacher]
      })

    {:ok, _member} =
      Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other_teacher}, inv.token)

    {:ok, tc_other} =
      Curriculum.assign_teacher(ctx.scope, ctx.unrelated, other_teacher, %{subject: "Anglais"})

    {:ok, tc_unrelated_head} =
      Curriculum.assign_teacher(ctx.scope, ctx.unrelated, ctx.head, %{subject: "Physique"})

    {:ok, _slot} =
      Timetabling.place_slot(ctx.scope, ctx.maco, %{
        day: :tuesday,
        period_id: ctx.period.id,
        teaching_context_id: ctx.tc_maco.id
      })

    assert {:ok, %TimetableSlot{}} =
             Timetabling.place_slot(ctx.scope, ctx.unrelated, %{
               day: :tuesday,
               period_id: ctx.period.id,
               teaching_context_id: tc_other.id
             })

    assert {:error, {:teacher_clash, "1ère MACO"}} =
             Timetabling.place_slot(ctx.scope, ctx.unrelated, %{
               day: :tuesday,
               period_id: ctx.period.id,
               teaching_context_id: tc_unrelated_head.id
             })
  end

  defp list_slots_for_cell(scope, day, period_id) do
    TimetableSlot
    |> Ash.Query.filter(day == ^day and period_id == ^period_id)
    |> Ash.read!(scope: scope)
  end
end
