defmodule TeacherAssistant.Academics.RollCallReminderTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{
    Attendance,
    Curriculum,
    Enrollment,
    Notifications,
    Organization,
    Timetabling
  }

  alias TeacherAssistant.TeacherFixtures

  # 2025-09-15 is a Monday; lesson 1 runs 07:30–08:20.
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
    teacher = TeacherFixtures.member_scope_fixture(scope)
    teacher = %{teacher | current_academic_year: year}
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, teacher.current_user, %{subject: "Anglais"})

    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, slot} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p1.id,
        teaching_context_id: tc.id
      })

    %{scope: scope, teacher: teacher, slot: slot}
  end

  test "« Relancer » notifies the slot's teacher once a day and marks the missed roll call",
       ctx do
    assert {:ok, r} = Attendance.remind_roll_call(ctx.scope, ctx.slot.id, @monday)
    assert r.date == @monday
    assert r.sent_by_user_id == ctx.scope.current_user.id

    assert %{unread: 1, latest: [n]} = Notifications.bell(ctx.teacher)
    assert n.kind == :roll_call_reminder
    assert n.link == "/school/today"
    assert n.params == %{"class" => "6e A", "time" => "07:30", "subject" => "Anglais"}

    assert {:error, :already_reminded} =
             Attendance.remind_roll_call(ctx.scope, ctx.slot.id, @monday)

    assert %{unread: 1} = Notifications.bell(ctx.teacher)

    day = Attendance.school_day(ctx.scope, @monday, ~N[2025-09-15 10:00:00])
    assert [%{reminded?: true, slot_id: slot_id}] = day.missed
    assert slot_id == ctx.slot.id

    # Another day starts fresh.
    assert {:ok, _} = Attendance.remind_roll_call(ctx.scope, ctx.slot.id, ~D[2025-09-22])
  end

  test "a missed roll call nobody reminded is not marked", ctx do
    assert [%{reminded?: false}] =
             Attendance.school_day(ctx.scope, @monday, ~N[2025-09-15 10:00:00]).missed
  end

  test "a teacher cannot remind", ctx do
    assert {:error, %Ash.Error.Forbidden{}} =
             Attendance.remind_roll_call(ctx.teacher, ctx.slot.id, @monday)
  end
end
