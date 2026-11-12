defmodule TeacherAssistant.Academics.LessonNotHeldTest do
  @moduledoc "Roll call outside the timetable (spec 2026-11-12): « déplacé à … » marked by the slot's teacher."
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.Academics.LessonNotHeld
  alias TeacherAssistant.TeacherFixtures

  require Ash.Query

  @monday ~D[2025-09-15]

  setup do
    head = TeacherFixtures.user_fixture()

    {:ok, ws} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "L"})

    scope = school_scope(head, ws)
    :ok = TeacherFixtures.verify_school!(scope)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    scope = %{scope | current_academic_year: year}
    _ = Organization.build_default_calendar(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, cg_b} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
    :ok = Attendance.build_default_periods(scope)

    [p1, p2, p3, p4 | _] =
      scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    # T teaches Maths at p1 (and a combined course over 6e A + 6e B at p4); U teaches
    # Anglais at p2; S manages conduct.
    scope_t = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    scope_u = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})
    scope_s = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})
    year_scope = fn s -> %{s | current_academic_year: year} end
    {:ok, tc_t} = Curriculum.assign_teacher(scope, cg, scope_t.current_user, %{subject: "Maths"})

    {:ok, tc_u} =
      Curriculum.assign_teacher(scope, cg, scope_u.current_user, %{subject: "Anglais"})

    {:ok, tc_tb} =
      Curriculum.assign_teacher(scope, cg_b, scope_t.current_user, %{subject: "Maths"})

    {:ok, course} = Curriculum.combine_course(scope, [tc_t, tc_tb])

    place = fn c, p, tc ->
      {:ok, _} =
        Timetabling.place_slot(scope, c, %{
          day: :monday,
          period_id: p.id,
          teaching_context_id: tc.id
        })
    end

    place.(cg, p1, tc_t)
    place.(cg, p2, tc_u)
    place.(cg, p4, tc_t)
    place.(cg_b, p4, tc_tb)

    %{
      scope: scope,
      scope_t: year_scope.(scope_t),
      scope_u: year_scope.(scope_u),
      scope_s: year_scope.(scope_s),
      cg: cg,
      cg_b: cg_b,
      course: course,
      p1: p1,
      p2: p2,
      p3: p3,
      p4: p4
    }
  end

  defp marking(scope, cg, period, date) do
    LessonNotHeld
    |> Ash.Query.filter(class_group_id == ^cg.id and period_id == ^period.id and date == ^date)
    |> Ash.Query.load(:moved_to_period)
    |> Ash.read_one!(scope: scope)
  end

  test "the slot's teacher marks it moved to another period", ctx do
    assert {:ok, %LessonNotHeld{moved_to_period_id: id}} =
             Attendance.mark_moved(ctx.scope_t, ctx.cg, ctx.p1, @monday, ctx.p3)

    assert id == ctx.p3.id
    assert marking(ctx.scope, ctx.cg, ctx.p1, @monday).moved_to_period.id == ctx.p3.id
  end

  test "another teacher is refused; a conduct manager is allowed", ctx do
    assert_forbidden(Attendance.mark_moved(ctx.scope_u, ctx.cg, ctx.p1, @monday, ctx.p3))
    assert {:ok, _} = Attendance.mark_moved(ctx.scope_s, ctx.cg, ctx.p1, @monday, ctx.p3)
  end

  test "a slot cannot be moved onto itself", ctx do
    assert {:error, error} = Attendance.mark_moved(ctx.scope_t, ctx.cg, ctx.p1, @monday, ctx.p1)
    assert Exception.message(error) =~ "propre créneau"
  end

  test "re-marking updates the motive", ctx do
    {:ok, _} = Attendance.mark_moved(ctx.scope_t, ctx.cg, ctx.p1, @monday, ctx.p3)
    {:ok, _} = Attendance.mark_moved(ctx.scope_t, ctx.cg, ctx.p1, @monday, ctx.p4)

    rows =
      LessonNotHeld
      |> Ash.Query.filter(class_group_id == ^ctx.cg.id and date == ^@monday)
      |> Ash.read!(scope: ctx.scope)

    assert [%{period_id: p1, moved_to_period_id: p4}] = rows
    assert {p1, p4} == {ctx.p1.id, ctx.p4.id}
  end

  test "the marker un-marks the same day, not the next", ctx do
    {:ok, _} = Attendance.mark_moved(ctx.scope_t, ctx.cg, ctx.p1, @monday, ctx.p3)
    assert :ok = Attendance.unmark_moved(ctx.scope_t, ctx.cg, ctx.p1, @monday)
    assert marking(ctx.scope, ctx.cg, ctx.p1, @monday) == nil

    {:ok, _} = Attendance.mark_moved(ctx.scope_t, ctx.cg, ctx.p1, @monday, ctx.p3)
    previous = Application.get_env(:teacher_assistant, :school_clock_now)
    Application.put_env(:teacher_assistant, :school_clock_now, ~U[2025-09-16 12:00:00Z])
    on_exit(fn -> Application.put_env(:teacher_assistant, :school_clock_now, previous) end)

    assert {:error, _} = Attendance.unmark_moved(ctx.scope_t, ctx.cg, ctx.p1, @monday)
    assert marking(ctx.scope, ctx.cg, ctx.p1, @monday) != nil
    # The surveillant still may.
    assert :ok = Attendance.unmark_moved(ctx.scope_s, ctx.cg, ctx.p1, @monday)
  end

  test "the teacher of a combined course marks a member class's slot", ctx do
    assert {:ok, _} = Attendance.mark_moved(ctx.scope_t, ctx.cg_b, ctx.p4, @monday, ctx.p3)
    assert_forbidden(Attendance.mark_moved(ctx.scope_u, ctx.cg_b, ctx.p4, @monday, ctx.p3))
  end
end
