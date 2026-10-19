defmodule TeacherAssistant.TimetablingReassignTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Accounts, Attendance, Curriculum, Enrollment, Organization, Timetabling}
  alias TeacherAssistant.TeacherFixtures

  setup do
    %{scope: scope} = TeacherFixtures.setup_complete_school_fixture()
    year = Organization.current_academic_year(scope)
    scope = %{scope | current_academic_year: year}
    _ = Attendance.build_default_periods(scope)
    [p1, p2 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    {:ok, a} = Enrollment.create_class_group(scope, year, %{label: "6e Q", level: "6ème"})
    {:ok, b} = Enrollment.create_class_group(scope, year, %{label: "6e R", level: "6ème"})

    owner = TeacherFixtures.member_scope_fixture(scope).current_user
    {:ok, tc} = Curriculum.assign_teacher(scope, a, owner, %{subject: "Maths", weekly_hours: 4})

    for p <- [p1, p2],
        do:
          {:ok, _} =
            Timetabling.place_slot(scope, a, %{
              day: :monday,
              period_id: p.id,
              teaching_context_id: tc.id
            })

    %{scope: scope, a: a, b: b, tc: tc, p1: p1, owner: owner}
  end

  defp teacher(scope, attrs \\ %{}) do
    member = TeacherFixtures.member_scope_fixture(scope, attrs)
    member.current_user
  end

  defp names(scope, tc),
    do:
      scope
      |> Timetabling.reassign_candidates(tc, Timetabling.school_slots(scope))
      |> Enum.map(& &1.user.id)

  test "a free teacher within their service is offered, with load and service", ctx do
    free = teacher(ctx.scope)

    assert [%{user: %{id: id}, load: 0, service: 18}] =
             Timetabling.reassign_candidates(
               ctx.scope,
               ctx.tc,
               Timetabling.school_slots(ctx.scope)
             )

    assert id == free.id
  end

  test "a teacher busy at one of the subject's slots is left out", ctx do
    busy = teacher(ctx.scope)
    {:ok, other} = Curriculum.assign_teacher(ctx.scope, ctx.b, busy, %{subject: "SVT"})

    {:ok, _} =
      Timetabling.place_slot(ctx.scope, ctx.b, %{
        day: :monday,
        period_id: ctx.p1.id,
        teaching_context_id: other.id
      })

    refute busy.id in names(ctx.scope, ctx.tc)
  end

  test "a teacher whose service the subject would exceed is left out", ctx do
    full = teacher(ctx.scope)
    {:ok, m} = Accounts.fetch_school_membership(ctx.scope, full)
    {:ok, _} = Accounts.set_member_service(ctx.scope, m, "5")

    {:ok, _} =
      Curriculum.assign_teacher(ctx.scope, ctx.b, full, %{subject: "SVT", weekly_hours: 2})

    refute full.id in names(ctx.scope, ctx.tc)
  end

  test "teachers of the subject come first, then the lightest load", ctx do
    light = teacher(ctx.scope)
    maths = teacher(ctx.scope)

    {:ok, _} =
      Curriculum.assign_teacher(ctx.scope, ctx.b, maths, %{subject: "Maths", weekly_hours: 3})

    assert names(ctx.scope, ctx.tc) == [maths.id, light.id]
  end

  test "non-teaching members are not offered", ctx do
    bursar = teacher(ctx.scope, %{roles: [:bursar]})
    refute bursar.id in names(ctx.scope, ctx.tc)
  end

  test "reassigning moves every slot of the subject to the new teacher", ctx do
    new = teacher(ctx.scope)
    {:ok, _} = Curriculum.reassign_teacher(ctx.scope, ctx.tc, new)

    assert ctx.scope
           |> Timetabling.school_slots()
           |> Enum.filter(&(&1.teaching_context_id == ctx.tc.id))
           |> Enum.all?(&(&1.teacher_id == new.id))
  end

  test "a teacher unavailable at one of the lesson's slots is not offered", ctx do
    blocked = teacher(ctx.scope)
    free = teacher(ctx.scope)
    :ok = Timetabling.set_unavailable(ctx.scope, blocked.id, [{:monday, ctx.p1.id}], true)

    ids =
      ctx.scope
      |> Timetabling.reassign_candidates(
        ctx.tc,
        Timetabling.school_slots(ctx.scope),
        Timetabling.unavailability(ctx.scope)
      )
      |> Enum.map(& &1.user.id)

    assert free.id in ids
    refute blocked.id in ids
  end
end
