defmodule TeacherAssistant.Workers.MissedRollCallsTest do
  use TeacherAssistant.DataCase, async: false
  use Oban.Testing, repo: TeacherAssistant.Repo

  import Ecto.Query

  alias TeacherAssistant.{
    Attendance,
    Curriculum,
    Enrollment,
    Notifications,
    Organization,
    TeacherFixtures,
    Timetabling
  }

  alias TeacherAssistant.Workers.MissedRollCalls

  @monday ~D[2025-09-15]

  setup do
    previous = Application.get_env(:teacher_assistant, :school_clock_now)
    # 12:30 school time (UTC+1).
    Application.put_env(:teacher_assistant, :school_clock_now, ~U[2025-09-15 11:30:00Z])

    on_exit(fn ->
      Application.put_env(:teacher_assistant, :school_clock_now, previous)
    end)

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
    {:ok, tc} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    [%{enrollment: e}] = Enrollment.list_roster(scope, cg)
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p1.id,
        teaching_context_id: tc.id
      })

    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

    %{
      scope: scope,
      head: head,
      sg: sg,
      teacher: teacher,
      cg: cg,
      tc: tc,
      e: e,
      p1: p1,
      year: year
    }
  end

  test "one notice per school listing the missed calls", ctx do
    assert :ok = perform_job(MissedRollCalls, %{"half" => "morning"})

    for scope <- [ctx.sg, ctx.scope] do
      assert [%{kind: :missed_roll_calls, params: params, link: "/school/day"}] =
               Notifications.inbox(scope, 1).results

      assert %{"count" => "1", "half" => "morning", "list" => list} = params
      assert list =~ "6e A 07:30"
    end

    # A retry of the same half-day sends nothing more.
    assert :ok = perform_job(MissedRollCalls, %{"half" => "morning"})
    assert length(Notifications.inbox(ctx.sg, 1).results) == 1
    assert length(Notifications.inbox(ctx.scope, 1).results) == 1

    # Not a teacher's business.
    assert Notifications.inbox(ctx.teacher, 1).results == []
  end

  test "the afternoon run ignores morning lessons", ctx do
    assert :ok = perform_job(MissedRollCalls, %{"half" => "afternoon"})
    assert Notifications.inbox(ctx.sg, 1).results == []
  end

  test "the half defaults from the school clock", ctx do
    assert :ok = perform_job(MissedRollCalls, %{})
    assert [%{params: %{"half" => "morning"}}] = Notifications.inbox(ctx.sg, 1).results
  end

  test "nothing when every call is done", ctx do
    {:ok, _} =
      Attendance.record_period(ctx.scope, ctx.cg, ctx.p1, ctx.tc, @monday, [{ctx.e.id, :present}])

    assert :ok = perform_job(MissedRollCalls, %{"half" => "morning"})
    assert Notifications.inbox(ctx.sg, 1).results == []
  end

  test "nothing on a holiday", ctx do
    {:ok, _} =
      Organization.create_holiday(ctx.scope, ctx.year, %{
        label: "Fête",
        start_date: @monday,
        end_date: @monday
      })

    assert :ok = perform_job(MissedRollCalls, %{"half" => "morning"})
    assert Notifications.inbox(ctx.sg, 1).results == []
  end

  test "nothing on a day without lessons", ctx do
    :ok = Timetabling.clear_slot(ctx.scope, ctx.cg, :monday, ctx.p1.id)

    {:ok, _} =
      Attendance.update_school_days(ctx.scope, %{
        "lesson_days" => ~w(tuesday wednesday),
        "default_lesson_minutes" => "50"
      })

    assert :ok = perform_job(MissedRollCalls, %{"half" => "morning"})
    assert Notifications.inbox(ctx.sg, 1).results == []
  end

  test "nothing for an unverified school", ctx do
    TeacherAssistant.Repo.update_all(
      from(p in "school_profiles",
        where: p.workspace_id == type(^ctx.scope.current_workspace.id, :binary_id)
      ),
      set: [verification_status: "unverified"]
    )

    assert :ok = perform_job(MissedRollCalls, %{"half" => "morning"})
    assert Notifications.inbox(ctx.sg, 1).results == []
  end
end
