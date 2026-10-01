defmodule TeacherAssistant.Academics.TimetableEditingTest do
  use TeacherAssistant.DataCase, async: true
  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Timetabling}
  alias TeacherAssistant.Academics.TimetableConflicts
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope, head_user: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    scope = %{scope | current_academic_year: year}
    :ok = Attendance.build_default_periods(scope)
    [p1, p2, p3 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    {:ok, a} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, b} = Enrollment.create_class_group(scope, year, %{label: "6e R", level: "6ème"})
    other = TeacherFixtures.membership_fixture(scope)
    {:ok, other_user} = Ash.get(TeacherAssistant.Accounts.User, other.user_id, authorize?: false)
    {:ok, ma} = Curriculum.assign_teacher(scope, a, head, %{subject: "Maths"})
    {:ok, mb} = Curriculum.assign_teacher(scope, b, head, %{subject: "Maths"})
    {:ok, sa} = Curriculum.assign_teacher(scope, a, other_user, %{subject: "SVT"})
    %{scope: scope, a: a, b: b, ma: ma, mb: mb, sa: sa, p1: p1, p2: p2, p3: p3}
  end

  defp place(ctx, cg, tc, day, p),
    do:
      {:ok, _} =
        Timetabling.place_slot(ctx.scope, cg, %{
          day: day,
          period_id: p.id,
          teaching_context_id: tc.id
        })

  test "school slots carry teacher and combined course; a clash is counted", ctx do
    place(ctx, ctx.a, ctx.ma, :monday, ctx.p1)
    place(ctx, ctx.b, ctx.mb, :monday, ctx.p1)
    slots = Timetabling.school_slots(ctx.scope)
    assert length(slots) == 2
    assert Enum.all?(slots, &(&1.teacher_id && Map.has_key?(&1, :combined_course_id)))
    assert TimetableConflicts.count(slots) == 1
  end

  test "move_slot moves a lesson to an empty open cell and clears the clash", ctx do
    place(ctx, ctx.a, ctx.ma, :monday, ctx.p1)
    place(ctx, ctx.b, ctx.mb, :monday, ctx.p1)

    assert :ok =
             Timetabling.move_slot(ctx.scope, ctx.a, {:monday, ctx.p1.id}, {:monday, ctx.p2.id})

    assert TimetableConflicts.count(Timetabling.school_slots(ctx.scope)) == 0
    assert Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p2.id}]
  end

  test "move_slot refuses an occupied target, and nothing changes", ctx do
    place(ctx, ctx.a, ctx.ma, :monday, ctx.p1)
    place(ctx, ctx.a, ctx.sa, :monday, ctx.p2)

    assert {:error, :occupied} =
             Timetabling.move_slot(ctx.scope, ctx.a, {:monday, ctx.p1.id}, {:monday, ctx.p2.id})

    slots = Timetabling.class_timetable(ctx.scope, ctx.a).slots
    assert slots[{:monday, ctx.p1.id}].teaching_context_id == ctx.ma.id
    assert slots[{:monday, ctx.p2.id}].teaching_context_id == ctx.sa.id
  end

  test "swap_slots exchanges two lessons of a class", ctx do
    place(ctx, ctx.a, ctx.ma, :monday, ctx.p1)
    place(ctx, ctx.a, ctx.sa, :tuesday, ctx.p1)

    assert :ok =
             Timetabling.swap_slots(ctx.scope, ctx.a, {:monday, ctx.p1.id}, {:tuesday, ctx.p1.id})

    slots = Timetabling.class_timetable(ctx.scope, ctx.a).slots
    assert slots[{:monday, ctx.p1.id}].teaching_context_id == ctx.sa.id
    assert slots[{:tuesday, ctx.p1.id}].teaching_context_id == ctx.ma.id
  end

  test "move and swap refuse an empty source and a plain teacher", ctx do
    assert {:error, :invalid} =
             Timetabling.move_slot(ctx.scope, ctx.a, {:monday, ctx.p3.id}, {:monday, ctx.p2.id})

    place(ctx, ctx.a, ctx.ma, :monday, ctx.p1)

    teacher = %{
      TeacherFixtures.member_scope_fixture(ctx.scope)
      | current_academic_year: ctx.scope.current_academic_year
    }

    assert {:error, _} =
             Timetabling.move_slot(teacher, ctx.a, {:monday, ctx.p1.id}, {:monday, ctx.p2.id})

    assert Timetabling.class_timetable(ctx.scope, ctx.a).slots[{:monday, ctx.p1.id}]
  end
end
