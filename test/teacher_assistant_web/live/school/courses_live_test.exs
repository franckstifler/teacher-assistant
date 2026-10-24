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
    |> put_user_in_session(user)
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

    case Date.day_of_week(TeacherAssistant.Academics.Reference.today()) do
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
    test "a plain teacher lands on their day from /school", %{
      school: school,
      teacher: teacher
    } do
      assert {:error, {:live_redirect, %{to: "/school/today"}}} =
               live(conn_for(school, teacher), ~p"/school")
    end

    test "a teacher who is also a form master lands on their day", %{
      school: school,
      teacher: teacher,
      cg: cg,
      scope: scope
    } do
      {:ok, _} = Enrollment.set_form_master(scope, cg, teacher.id)

      assert {:error, {:live_redirect, %{to: "/school/today"}}} =
               live(conn_for(school, teacher), ~p"/school")
    end

    test "staff without a teaching space land on their space home (bursar, discipline master)", %{
      school: school,
      scope: scope
    } do
      for {role, home} <- [bursar: "/school/fees", discipline_master: "/school/day"] do
        staff = TeacherAssistant.TeacherFixtures.user_fixture()

        {:ok, inv} =
          Accounts.invite_member(scope, %{email: to_string(staff.email), roles: [role]})

        {:ok, _} =
          Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: staff}, inv.token)

        assert {:error, {:live_redirect, %{to: ^home}}} =
                 live(conn_for(school, staff), ~p"/school")
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
      assert has_element?(view, "#dashboard")
      assert has_element?(view, "#dashboard-my-courses a[href='/school/courses']")
    end
  end

  describe "course card facts" do
    setup %{scope: scope, year: year, school: school, teacher: teacher} do
      {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e Z", level: "6ème"})
      maths = Enum.find(Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))

      :ok =
        Curriculum.update_coefficient_grid(scope, %{
          "cells" => %{maths.id => %{Curriculum.cell_token({:francophone, "6ème", nil}) => "4"}},
          "groups" => %{}
        })

      {:ok, tc} = Curriculum.place_assignment(scope, cg, maths, teacher.id, "4")
      {:ok, cg} = Enrollment.set_form_master(scope, cg, teacher.id)
      {:ok, s1} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
      {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})

      seq =
        TeacherAssistant.Assessment.default_sequence(
          Organization.list_sequences(scope, year),
          TeacherAssistant.Academics.Reference.today()
        )

      :ok = TeacherAssistant.TeacherFixtures.verify_school!(scope)
      {:ok, a} = TeacherAssistant.Assessment.create_assessment(scope, tc, seq, %{label: "D1"})

      :ok =
        TeacherAssistant.Assessment.upsert_marks(scope, a, [
          %{student_id: s1.id, score: Decimal.new(12)}
        ])

      %{card_tc: tc, conn: conn_for(school, teacher)}
    end

    test "a card shows students, coefficient, PP and séquence progress", %{
      conn: conn,
      card_tc: tc
    } do
      {:ok, view, _} = live(conn, ~p"/school/courses")
      card = "#course-#{tc.id}"
      assert has_element?(view, card, "2 élèves")
      assert has_element?(view, card, "coef. 4")
      assert has_element?(view, "#{card} [data-role='pp']")
      assert has_element?(view, "#{card} [data-role='progress']", "1 / 2")
    end
  end

  test "the subtitle counts a class taught in two subjects once", %{
    school: school,
    teacher: teacher,
    cg: cg,
    scope: scope
  } do
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Curriculum.assign_teacher(scope, cg, teacher, %{subject: "Physique"})

    {:ok, view, _} = live(conn_for(school, teacher), ~p"/school/courses")
    assert has_element?(view, "#courses header", "2 cours · 1 élève")
  end
end
