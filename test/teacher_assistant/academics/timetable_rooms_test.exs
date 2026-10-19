defmodule TeacherAssistant.Academics.TimetableRoomsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.Academics.Subject
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, year: year} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    _ = Attendance.build_default_periods(scope)
    [p1, p2 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, a} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, b} = Enrollment.create_class_group(scope, year, %{label: "6e R", level: "6ème"})

    t1 = TeacherFixtures.member_scope_fixture(scope).current_user
    t2 = TeacherFixtures.member_scope_fixture(scope).current_user

    {:ok, info} = Organization.create_room(scope, %{name: "Salle info", kind: :computer_room})

    {:ok, labo} =
      Organization.create_room(scope, %{name: "Labo", kind: :laboratory, capacity: 40})

    {:ok, b12} = Organization.create_room(scope, %{name: "B12"})
    {:ok, a} = Enrollment.set_home_room(scope, a, b12.id)

    {:ok, it} = Curriculum.assign_teacher(scope, a, t1, %{subject: "Informatique"})
    {:ok, maths} = Curriculum.assign_teacher(scope, a, t2, %{subject: "Maths"})
    subject = Ash.get!(Subject, it.subject_id, scope: scope)
    {:ok, _} = Curriculum.update_subject(scope, subject, %{default_room_id: info.id})

    %{
      scope: scope,
      year: year,
      a: a,
      b: b,
      p1: p1,
      p2: p2,
      t1: t1,
      t2: t2,
      info: info,
      labo: labo,
      b12: b12,
      it: it,
      maths: maths
    }
  end

  defp place(ctx, cg, tc, day, period),
    do:
      Timetabling.place_slot(ctx.scope, cg, %{
        day: day,
        period_id: period.id,
        teaching_context_id: tc.id
      })

  defp slot_at(ctx, cg, day, period) do
    [slot] = Timetabling.list_for_cell!(cg.id, day, period.id, scope: ctx.scope)
    slot
  end

  test "placing a course whose subject has a default room puts the lesson there", ctx do
    assert {:ok, slot} = place(ctx, ctx.a, ctx.it, :monday, ctx.p1)
    assert slot.room_id == ctx.info.id
    assert {:ok, %{room_id: nil}} = place(ctx, ctx.a, ctx.maths, :monday, ctx.p2)
  end

  test "a deactivated default room is skipped (room_id nil)", ctx do
    {:ok, _} = Organization.update_room(ctx.scope, ctx.info, %{active?: false})
    assert {:ok, %{room_id: nil}} = place(ctx, ctx.a, ctx.it, :monday, ctx.p1)
  end

  test "re-placing the same course on its cell keeps a hand-picked room", ctx do
    {:ok, _} = place(ctx, ctx.a, ctx.it, :monday, ctx.p1)
    :ok = Timetabling.set_slot_room(ctx.scope, ctx.a, {:monday, ctx.p1.id}, ctx.labo.id)
    {:ok, _} = place(ctx, ctx.a, ctx.it, :monday, ctx.p1)
    assert slot_at(ctx, ctx.a, :monday, ctx.p1).room_id == ctx.labo.id
  end

  test "replacing the occupant with another course recomputes the room", ctx do
    {:ok, _} = place(ctx, ctx.a, ctx.it, :monday, ctx.p1)
    {:ok, _} = place(ctx, ctx.a, ctx.maths, :monday, ctx.p1)
    assert slot_at(ctx, ctx.a, :monday, ctx.p1).room_id == nil
  end

  test "move keeps the room; swap exchanges the rooms with the courses", ctx do
    {:ok, _} = place(ctx, ctx.a, ctx.it, :monday, ctx.p1)
    :ok = Timetabling.move_slot(ctx.scope, ctx.a, {:monday, ctx.p1.id}, {:tuesday, ctx.p1.id})
    assert slot_at(ctx, ctx.a, :tuesday, ctx.p1).room_id == ctx.info.id

    {:ok, _} = place(ctx, ctx.a, ctx.maths, :tuesday, ctx.p2)
    :ok = Timetabling.swap_slots(ctx.scope, ctx.a, {:tuesday, ctx.p1.id}, {:tuesday, ctx.p2.id})

    moved = slot_at(ctx, ctx.a, :tuesday, ctx.p2)
    assert moved.teaching_context_id == ctx.it.id and moved.room_id == ctx.info.id
    other = slot_at(ctx, ctx.a, :tuesday, ctx.p1)
    assert other.teaching_context_id == ctx.maths.id and other.room_id == nil
  end

  test "set_slot_room sets, clears, and refuses an inactive or foreign room and an empty cell",
       ctx do
    {:ok, _} = place(ctx, ctx.a, ctx.maths, :monday, ctx.p1)
    cell = {:monday, ctx.p1.id}

    assert :ok = Timetabling.set_slot_room(ctx.scope, ctx.a, cell, ctx.labo.id)
    assert slot_at(ctx, ctx.a, :monday, ctx.p1).room_id == ctx.labo.id
    assert :ok = Timetabling.set_slot_room(ctx.scope, ctx.a, cell, nil)
    assert slot_at(ctx, ctx.a, :monday, ctx.p1).room_id == nil

    {:ok, off} = Organization.create_room(ctx.scope, %{name: "Vieille salle", active?: false})
    assert {:error, :invalid} = Timetabling.set_slot_room(ctx.scope, ctx.a, cell, off.id)

    %{scope: other} = TeacherFixtures.setup_complete_school_fixture()
    {:ok, foreign} = Organization.create_room(other, %{name: "Ailleurs"})
    assert {:error, :invalid} = Timetabling.set_slot_room(ctx.scope, ctx.a, cell, foreign.id)

    assert {:error, :invalid} =
             Timetabling.set_slot_room(ctx.scope, ctx.a, {:monday, ctx.p2.id}, ctx.labo.id)

    assert slot_at(ctx, ctx.a, :monday, ctx.p1).room_id == nil
  end

  test "a combined course gets one room on every member class, by place and by set_slot_room",
       ctx do
    {:ok, it_b} = Curriculum.assign_teacher(ctx.scope, ctx.b, ctx.t1, %{subject: "Informatique"})
    {:ok, course} = Curriculum.combine_course(ctx.scope, [ctx.it, it_b])

    {:ok, slots} = Timetabling.place_combined_slot(ctx.scope, course, :monday, ctx.p1.id)
    assert Enum.map(slots, & &1.room_id) == [ctx.info.id, ctx.info.id]

    :ok = Timetabling.set_slot_room(ctx.scope, ctx.b, {:monday, ctx.p1.id}, ctx.labo.id)
    assert slot_at(ctx, ctx.a, :monday, ctx.p1).room_id == ctx.labo.id
    assert slot_at(ctx, ctx.b, :monday, ctx.p1).room_id == ctx.labo.id
  end

  test "school_slots resolves the effective room, home room and class size", ctx do
    {:ok, _} = Enrollment.enroll_new(ctx.scope, ctx.a, %{full_name: "Awa A", sex: :f})
    {:ok, _} = place(ctx, ctx.a, ctx.it, :monday, ctx.p1)
    {:ok, _} = place(ctx, ctx.a, ctx.maths, :monday, ctx.p2)

    by_period = ctx.scope |> Timetabling.school_slots() |> Map.new(&{&1.period_id, &1})
    assert %{room_id: info, home_room_id: b12, class_size: 1} = by_period[ctx.p1.id]
    assert info == ctx.info.id and b12 == ctx.b12.id
    assert by_period[ctx.p2.id].room_id == ctx.b12.id

    assert Timetabling.room_capacities(ctx.scope)[ctx.labo.id] == 40
  end

  test "class_timetable shows the shared room's name, and the home room's when no room is set",
       ctx do
    {:ok, _} = place(ctx, ctx.a, ctx.it, :monday, ctx.p1)
    {:ok, _} = place(ctx, ctx.a, ctx.maths, :monday, ctx.p2)

    slots = Timetabling.class_timetable(ctx.scope, ctx.a).slots
    assert slots[{:monday, ctx.p1.id}].room_name == "Salle info"
    assert slots[{:monday, ctx.p2.id}].room_name == "B12"

    [view] = Timetabling.teacher_timetable(ctx.scope, ctx.t1)[{:monday, ctx.p1.id}]
    assert view.room_name == "Salle info"
  end

  test "set_slot_room returns an error instead of raising when the write is refused", ctx do
    {:ok, _} = place(ctx, ctx.a, ctx.maths, :monday, ctx.p1)
    teacher = TeacherFixtures.member_scope_fixture(ctx.scope)
    teacher = %{teacher | current_academic_year: ctx.year}

    assert {:error, _} =
             Timetabling.set_slot_room(teacher, ctx.a, {:monday, ctx.p1.id}, ctx.labo.id)

    assert slot_at(ctx, ctx.a, :monday, ctx.p1).room_id == nil
  end

  test "re-placing a combined course after one member cell changed keeps the hand-picked room",
       ctx do
    {:ok, it_b} = Curriculum.assign_teacher(ctx.scope, ctx.b, ctx.t1, %{subject: "Informatique"})
    {:ok, course} = Curriculum.combine_course(ctx.scope, [ctx.it, it_b])
    {:ok, _} = Timetabling.place_combined_slot(ctx.scope, course, :monday, ctx.p1.id)
    :ok = Timetabling.set_slot_room(ctx.scope, ctx.a, {:monday, ctx.p1.id}, ctx.labo.id)

    # 6e Q's cell gets another course, then the combined course goes back
    {:ok, _} = place(ctx, ctx.a, ctx.maths, :monday, ctx.p1)
    {:ok, _} = Timetabling.place_combined_slot(ctx.scope, course, :monday, ctx.p1.id)

    assert slot_at(ctx, ctx.a, :monday, ctx.p1).room_id == ctx.labo.id
    assert slot_at(ctx, ctx.b, :monday, ctx.p1).room_id == ctx.labo.id
  end
end
