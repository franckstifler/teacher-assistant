defmodule TeacherAssistant.Academics.TimetablesCombinedTest do
  use TeacherAssistant.DataCase, async: true

  require Ash.Query

  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Assignments
  alias TeacherAssistant.Academics.Courses
  alias TeacherAssistant.Academics.Timetables
  alias TeacherAssistant.Academics.TimetableSlot
  alias TeacherAssistant.Accounts.Schools
  alias TeacherAssistant.TeacherFixtures

  setup do
    head = TeacherFixtures.user_fixture()
    {:ok, ws} = Schools.create_school(head, %{name: "Lycée Combiné"})

    {:ok, year} =
      Academics.create_academic_year(ws, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, maco} = Academics.create_class_group(ws, year, %{label: "1ère MACO", level: "1ère"})
    {:ok, menu} = Academics.create_class_group(ws, year, %{label: "1ère MENU", level: "1ère"})
    {:ok, unrelated} = Academics.create_class_group(ws, year, %{label: "1ère C", level: "1ère"})

    {:ok, tc_maco} = Assignments.assign(maco, head, %{subject: "Maths"})
    {:ok, tc_menu} = Assignments.assign(menu, head, %{subject: "Maths"})

    {:ok, course} = Courses.combine([tc_maco, tc_menu])

    :ok = Timetables.build_default_periods(ws)
    period = Timetables.list_periods(ws) |> Enum.find(&(&1.kind == :lesson))

    %{
      head: head,
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
    assert {:ok, slots} = Timetables.place_combined_slot(ctx.course, :monday, ctx.period.id)

    assert length(slots) == 2
    class_group_ids = Enum.map(slots, & &1.class_group_id) |> Enum.sort()
    assert class_group_ids == Enum.sort([ctx.maco.id, ctx.menu.id])

    maco_slot = Enum.find(slots, &(&1.class_group_id == ctx.maco.id))
    menu_slot = Enum.find(slots, &(&1.class_group_id == ctx.menu.id))

    assert maco_slot.teaching_context_id == ctx.tc_maco.id
    assert menu_slot.teaching_context_id == ctx.tc_menu.id

    assert length(list_slots_for_cell(ctx.ws, :monday, ctx.period.id)) == 2
  end

  test "clear_combined_slot removes both member slots and is idempotent", ctx do
    {:ok, _slots} = Timetables.place_combined_slot(ctx.course, :monday, ctx.period.id)

    assert :ok = Timetables.clear_combined_slot(ctx.course, :monday, ctx.period.id)
    assert list_slots_for_cell(ctx.ws, :monday, ctx.period.id) == []
    assert :ok = Timetables.clear_combined_slot(ctx.course, :monday, ctx.period.id)
  end

  test "a genuine clash between an unrelated class and the combined course's teacher is still rejected",
       ctx do
    {:ok, tc_unrelated} = Assignments.assign(ctx.unrelated, ctx.head, %{subject: "Physique"})

    {:ok, _slot} =
      Timetables.place_slot(ctx.unrelated, %{
        day: :monday,
        period_id: ctx.period.id,
        teaching_context_id: tc_unrelated.id
      })

    assert {:error, {:teacher_clash, "1ère C"}} =
             Timetables.place_combined_slot(ctx.course, :monday, ctx.period.id)

    assert list_slots_for_cell(ctx.ws, :monday, ctx.period.id)
           |> Enum.reject(&(&1.class_group_id == ctx.unrelated.id)) == []
  end

  test "a genuine clash between two unrelated ordinary classes is still rejected", ctx do
    other_teacher = TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(ctx.ws, ctx.head, %{
        email: to_string(other_teacher.email),
        roles: [:teacher]
      })

    {:ok, _member} = Schools.accept_invitation(inv.token, other_teacher)

    {:ok, tc_other} = Assignments.assign(ctx.unrelated, other_teacher, %{subject: "Anglais"})
    {:ok, tc_unrelated_head} = Assignments.assign(ctx.unrelated, ctx.head, %{subject: "Physique"})

    {:ok, _slot} =
      Timetables.place_slot(ctx.maco, %{
        day: :tuesday,
        period_id: ctx.period.id,
        teaching_context_id: ctx.tc_maco.id
      })

    assert {:ok, %TimetableSlot{}} =
             Timetables.place_slot(ctx.unrelated, %{
               day: :tuesday,
               period_id: ctx.period.id,
               teaching_context_id: tc_other.id
             })

    assert {:error, {:teacher_clash, "1ère MACO"}} =
             Timetables.place_slot(ctx.unrelated, %{
               day: :tuesday,
               period_id: ctx.period.id,
               teaching_context_id: tc_unrelated_head.id
             })
  end

  defp list_slots_for_cell(ws, day, period_id) do
    TimetableSlot
    |> Ash.Query.filter(workspace_id == ^ws.id and day == ^day and period_id == ^period_id)
    |> Ash.read!(authorize?: false)
  end
end
