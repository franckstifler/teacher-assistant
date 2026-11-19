defmodule TeacherAssistantWeb.School.MemberProfileTodayLiveTest do
  # Moves the school clock to a Wednesday: alone and not async, so no other module
  # sees it.
  use TeacherAssistantWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Accounts, Attendance, Curriculum, Enrollment, Organization}
  alias TeacherAssistant.{TeacherFixtures, Timetabling}

  setup :register_and_log_in_user

  test "the member's timetable opens on today when it is a school day", %{conn: conn, actor: head} do
    previous = Application.get_env(:teacher_assistant, :school_clock_now)
    Application.put_env(:teacher_assistant, :school_clock_now, ~U[2025-09-17 12:00:00Z])
    on_exit(fn -> Application.put_env(:teacher_assistant, :school_clock_now, previous) end)

    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Today"})

    scope = school_scope(head, school)
    TeacherFixtures.complete_school_setup!(scope)
    scope = school_scope(head, school)
    class = hd(Enrollment.list_class_groups(scope, scope.current_academic_year))

    {:ok, %{user: teacher}} =
      Accounts.add_member_by_phone(scope, %{
        name: "Awa Today",
        phone: "677123457",
        roles: [:teacher]
      })

    {:ok, member} = Accounts.fetch_school_membership(scope, teacher)
    {:ok, tc} = Curriculum.assign_teacher(scope, class, teacher, %{subject: "Maths"})
    :ok = Attendance.build_default_periods(scope)
    p = Enum.find(Attendance.list_periods(scope), &(&1.kind == :lesson))

    {:ok, _} =
      Timetabling.place_slot(scope, class, %{
        day: :monday,
        period_id: p.id,
        teaching_context_id: tc.id
      })

    conn = post(conn, ~p"/workspaces/select/#{school.id}")
    {:ok, view, _} = live(conn, ~p"/school/members/#{member.id}?tab=timetable")

    assert has_element?(view, "#member-day-wednesday[aria-pressed=true][aria-current=date]")
    assert has_element?(view, "#member-day-monday[aria-pressed=false]")
    assert has_element?(view, "#member-day-lessons", "Aucun cours ce jour")
  end
end
