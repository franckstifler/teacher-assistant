defmodule TeacherAssistant.Workers.PaperSheetsOverdueTest do
  use TeacherAssistant.DataCase, async: false
  use Oban.Testing, repo: TeacherAssistant.Repo

  alias TeacherAssistant.{
    Attendance,
    Curriculum,
    Enrollment,
    Notifications,
    Organization,
    TeacherFixtures,
    Timetabling
  }

  alias TeacherAssistant.Workers.PaperSheetsOverdue
  alias TeacherAssistantWeb.NotificationText

  setup do
    previous = Application.get_env(:teacher_assistant, :school_clock_now)
    # Monday 2025-09-22, 06:30 school time (UTC+1): the week of the 15th is over.
    Application.put_env(:teacher_assistant, :school_clock_now, ~U[2025-09-22 05:30:00Z])
    on_exit(fn -> Application.put_env(:teacher_assistant, :school_clock_now, previous) end)

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
    :ok = Attendance.build_default_periods(scope)
    [p1 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, cg, %{
        day: :monday,
        period_id: p1.id,
        teaching_context_id: tc.id
      })

    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})
    sg = %{sg | current_academic_year: year}
    %{scope: scope, sg: sg, cg: cg, p1: p1}
  end

  test "the SG hears of paper sheets not typed in, oldest week first", ctx do
    assert :ok = perform_job(PaperSheetsOverdue, %{})

    assert [%{kind: :paper_sheets_overdue, params: params, link: link}] =
             Notifications.inbox(ctx.sg, 1).results

    assert %{"count" => "2", "list" => list} = params
    assert list == "6e A (sem. du 8 sept.), 6e A (sem. du 15 sept.)"
    assert link == "/school/classes/#{ctx.cg.id}/roll-sheet?week=2025-09-08"
  end

  test "nothing once every past week is typed in", ctx do
    for monday <- [~D[2025-09-08], ~D[2025-09-15]] do
      {:ok, _} =
        Attendance.save_paper_week(ctx.sg, ctx.cg, monday, [
          %{date: monday, period_id: ctx.p1.id, mode: :taken, marks: %{}}
        ])
    end

    assert :ok = perform_job(PaperSheetsOverdue, %{})
    assert Notifications.inbox(ctx.sg, 1).results == []
  end

  test "a class off paper is not in it", ctx do
    {:ok, _} = Enrollment.set_paper_roll_call(ctx.scope, ctx.cg, false)
    assert :ok = perform_job(PaperSheetsOverdue, %{})
    assert Notifications.inbox(ctx.sg, 1).results == []
  end

  test "the notice reads « N feuilles d'appel non saisies »" do
    notice = %{
      kind: :paper_sheets_overdue,
      params: %{"count" => "1", "list" => "6e A (sem. du 8 sept.)"}
    }

    assert NotificationText.title(notice) == "1 feuille d'appel non saisie"
    assert NotificationText.detail(notice) == "6e A (sem. du 8 sept.)"
  end
end
