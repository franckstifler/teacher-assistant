defmodule TeacherAssistantWeb.School.CoursesLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Attendance
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
        name: "Lycée Cours"
      })

    scope = school_scope(head, school)
    year = TeacherAssistant.TeacherFixtures.complete_school_setup!(scope)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "3e M2", level: "3ème"})

    teacher = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(scope, %{email: to_string(teacher.email), roles: [:teacher]})

    {:ok, _} =
      Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: teacher}, inv.token)

    {:ok, tc} = Curriculum.assign_teacher(scope, cg, teacher, %{subject: "Maths"})

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)

    %{
      conn: conn,
      school: school,
      year: year,
      cg: cg,
      teacher: teacher,
      tc: tc,
      head: head,
      scope: scope
    }
  end

  defp conn_for(school, user) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  test "an assigned teacher sees one row per course with its four links", %{
    school: school,
    teacher: teacher,
    cg: cg,
    tc: tc,
    scope: scope
  } do
    {:ok, view, _html} = live(conn_for(school, teacher), ~p"/school/courses")

    assert has_element?(view, "#courses")
    assert has_element?(view, "#course-#{tc.id}", "Maths")
    assert has_element?(view, "#course-#{tc.id}", "3e M2")
    assert has_element?(view, "#course-#{tc.id} a[href='/teacher/contexts/#{tc.id}/roster']")
    assert has_element?(view, "#course-#{tc.id} a[href='/teacher/contexts/#{tc.id}/marks']")

    assert has_element?(
             view,
             "#course-#{tc.id} a[href='/teacher/contexts/#{tc.id}/marks/summary']"
           )

    first_lesson = scope |> Attendance.list_periods() |> Enum.find(&(&1.kind == :lesson))

    assert has_element?(
             view,
             "#course-#{tc.id} a[href^='/school/classes/#{cg.id}/attendance/#{first_lesson.id}?date=']"
           )
  end

  test "the Appel link targets the teacher's own slot period, not a colleague's", %{
    school: school,
    teacher: teacher,
    cg: cg,
    tc: tc,
    head: head,
    scope: scope
  } do
    [p1, p2 | _] = scope |> Attendance.list_periods() |> Enum.filter(&(&1.kind == :lesson))
    {:ok, tc_head} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Physique"})

    case Date.day_of_week(Date.utc_today()) do
      7 ->
        # No lessons on Sunday: the link falls back to the first lesson period.
        {:ok, view, _html} = live(conn_for(school, teacher), ~p"/school/courses")
        assert has_element?(view, "#course-#{tc.id} a[href*='/attendance/#{p1.id}?']")

      n ->
        day = Enum.at(~w(monday tuesday wednesday thursday friday saturday)a, n - 1)

        {:ok, _} =
          TeacherAssistant.Timetabling.place_slot(scope, cg, %{
            day: day,
            period_id: p1.id,
            teaching_context_id: tc_head.id
          })

        {:ok, _} =
          TeacherAssistant.Timetabling.place_slot(scope, cg, %{
            day: day,
            period_id: p2.id,
            teaching_context_id: tc.id
          })

        {:ok, view, _html} = live(conn_for(school, teacher), ~p"/school/courses")
        assert has_element?(view, "#course-#{tc.id} a[href*='/attendance/#{p2.id}?']")
        refute has_element?(view, "#course-#{tc.id} a[href*='/attendance/#{p1.id}?']")
    end
  end

  test "a combined course is one row, not one per class", %{
    school: school,
    year: year,
    teacher: teacher,
    cg: cg,
    tc: tc,
    scope: scope
  } do
    {:ok, cg_b} = Enrollment.create_class_group(scope, year, %{label: "3e M3", level: "3ème"})
    {:ok, tc_b} = Curriculum.assign_teacher(scope, cg_b, teacher, %{subject: "Maths"})
    {:ok, course} = Curriculum.combine_course(scope, [tc, tc_b])

    {:ok, view, _html} = live(conn_for(school, teacher), ~p"/school/courses")

    assert has_element?(view, "#course-combined-#{course.id}", course.label)
    assert has_element?(view, "#course-combined-#{course.id}", cg.label)
    assert has_element?(view, "#course-combined-#{course.id}", cg_b.label)
    refute has_element?(view, "#course-#{tc.id}")
    refute has_element?(view, "#course-#{tc_b.id}")
  end

  test "a member with no assignment sees the empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/school/courses")
    assert has_element?(view, "#courses-empty")
  end

  test "the rail shows Mes cours only to members with an assignment", %{
    conn: conn,
    school: school,
    teacher: teacher
  } do
    {:ok, view, _html} = live(conn_for(school, teacher), ~p"/school/courses")
    assert has_element?(view, "#nav-school-courses")

    {:ok, view, _html} = live(conn, ~p"/school")
    refute has_element?(view, "#nav-school-courses")
  end

  describe "landing rule" do
    test "a plain teacher lands on their courses from /school", %{
      school: school,
      teacher: teacher
    } do
      assert {:error, {:live_redirect, %{to: "/school/courses"}}} =
               live(conn_for(school, teacher), ~p"/school")
    end

    test "a teacher who is also a form master keeps the dashboard", %{
      school: school,
      teacher: teacher,
      cg: cg,
      scope: scope
    } do
      {:ok, _} = Enrollment.set_form_master(scope, cg, teacher.id)
      {:ok, view, _html} = live(conn_for(school, teacher), ~p"/school")
      assert has_element?(view, "#school-dashboard")
      assert has_element?(view, "#dashboard-my-courses a[href='/school/courses']")
    end

    test "staff without a management-free role keep the dashboard (bursar, discipline master)", %{
      school: school,
      scope: scope
    } do
      for role <- [:bursar, :discipline_master] do
        staff = TeacherAssistant.TeacherFixtures.user_fixture()

        {:ok, inv} =
          Accounts.invite_member(scope, %{email: to_string(staff.email), roles: [role]})

        {:ok, _} =
          Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: staff}, inv.token)

        {:ok, view, _html} = live(conn_for(school, staff), ~p"/school")
        assert has_element?(view, "#school-dashboard")
      end
    end

    test "the head keeps the dashboard even when teaching", %{
      conn: conn,
      cg: cg,
      head: head,
      scope: scope
    } do
      {:ok, _} = Curriculum.assign_teacher(scope, cg, head, %{subject: "Physique"})
      {:ok, view, _html} = live(conn, ~p"/school")
      assert has_element?(view, "#school-dashboard")
      assert has_element?(view, "#dashboard-my-courses a[href='/school/courses']")
    end
  end
end
