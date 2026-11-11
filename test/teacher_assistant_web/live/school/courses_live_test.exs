defmodule TeacherAssistantWeb.School.CoursesLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts
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

  test "an assigned teacher sees one row per course, under its subject, opening its marks", %{
    school: school,
    teacher: teacher,
    tc: tc
  } do
    {:ok, view, _html} = live(conn_for(school, teacher), ~p"/school/courses")

    assert has_element?(view, "#courses section[aria-label='Maths'] h2", "Maths · 1 cours")
    assert has_element?(view, "#course-#{tc.id}", "3e M2")
    assert has_element?(view, "#course-#{tc.id} a[href='/teacher/contexts/#{tc.id}/marks']")
    # results and roster are the course's tabs now; the roll call is the day's
    refute has_element?(view, "#course-#{tc.id} a[href$='/roster']")
    refute has_element?(view, "#course-#{tc.id} a[href*='/attendance/']")
    # no evaluation yet in the séquence
    assert has_element?(view, "#course-#{tc.id} [data-role='progress']", "0 éval.")
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

    assert has_element?(view, "#course-combined-#{course.id}", "2 classes")
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

      %{card_tc: tc, card_seq: seq, conn: conn_for(school, teacher)}
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
      assert has_element?(view, "#{card} [data-role='progress']", "1/2")
    end

    test "filter pills count the courses with marks or a competence to enter", %{
      conn: conn,
      card_tc: tc,
      tc: other
    } do
      {:ok, view, _} = live(conn, ~p"/school/courses")
      assert has_element?(view, "#filter-all", "2")
      assert has_element?(view, "#filter-marks", "2")
      refute has_element?(view, "#filter-competence")

      view |> element("#filter-marks") |> render_click()
      assert_patch(view, ~p"/school/courses?f=marks")
      assert has_element?(view, "#course-#{tc.id}")
      assert has_element?(view, "#course-#{other.id}")
      assert has_element?(view, "#filter-marks[aria-current='true']")
    end

    test "no competence line when the school's report cards are not APC", %{
      conn: conn,
      card_tc: tc
    } do
      {:ok, view, _} = live(conn, ~p"/school/courses")
      refute has_element?(view, "#course-#{tc.id} [data-role='competence']")
    end

    test "an APC school flags the séquence competence to enter, then ticks it", %{
      conn: conn,
      card_tc: tc,
      card_seq: seq,
      scope: scope
    } do
      {:ok, _} =
        TeacherAssistant.Assessment.update_bulletin_settings(scope, %{
          "language" => "by_class",
          "elements" => ["apc", "rank"]
        })

      {:ok, view, _} = live(conn, ~p"/school/courses")
      line = "#course-#{tc.id} [data-role='competence']"
      assert has_element?(view, line, "Compétence Séq. #{seq.number} : à saisir")

      assert has_element?(view, "#filter-competence", "2")

      assert has_element?(
               view,
               "#course-#{tc.id} a[href='/teacher/contexts/#{tc.id}/marks?seq=#{seq.id}']"
             )

      :ok =
        TeacherAssistant.Assessment.put_sequence_competence(scope, tc, seq, "Lire un graphique")

      {:ok, view, _} = live(conn, ~p"/school/courses")
      assert has_element?(view, line, "Compétence Séq. #{seq.number} ✓")
      assert has_element?(view, "#course-#{tc.id} a[href='/teacher/contexts/#{tc.id}/marks']")
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
    assert has_element?(view, "#courses-subtitle", "2 cours · 1 élève")
  end

  test "a teacher prints the working lists of all their classes", %{
    school: school,
    teacher: teacher
  } do
    {:ok, view, _html} = live(conn_for(school, teacher), ~p"/school/courses")

    assert has_element?(
             view,
             "#print-all-class-lists[href='/teacher/class-lists/print'][target='_blank']"
           )
  end

  test "no print link without a course", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/school/courses")
    refute has_element?(view, "#print-all-class-lists")
  end

  describe "bulletin timeline (A5)" do
    test "Mes cours shows the trimester pills and the timeline, current step first", ctx do
      [term | _] = Organization.list_terms(ctx.scope, ctx.year)
      {:ok, view, _} = live(conn_for(ctx.school, ctx.teacher), ~p"/school/courses")

      assert has_element?(view, "#courses-period-tabs #period-trim-#{term.id}[aria-current]")
      assert has_element?(view, "#courses-period-tabs #period-annee")
      refute has_element?(view, "#courses-period-tabs [id^='period-seq-']")
      assert has_element?(view, "#bulletin-timeline-current", "Notes de la séquence 1")
      assert has_element?(view, "#bulletin-steps li[data-state=now]", "Notes de la séquence 1")

      assert has_element?(
               view,
               "#bulletin-steps li[data-state=later]",
               "Publication des bulletins"
             )
    end

    test "the year pill shows every séquence of the year", ctx do
      {:ok, view, _} = live(conn_for(ctx.school, ctx.teacher), ~p"/school/courses?period=annee")
      assert has_element?(view, "#period-annee[aria-current]")
      n = length(Organization.list_sequences(ctx.scope, ctx.year))

      assert view
             |> element("#bulletin-steps")
             |> render()
             |> then(&(length(String.split(&1, "Notes de la séquence")) - 1)) == n
    end

    test "the timeline marks a published trimester done", ctx do
      [term | _] = Organization.list_terms(ctx.scope, ctx.year)
      :ok = TeacherAssistant.TeacherFixtures.verify_school!(ctx.scope)
      {:ok, _} = TeacherAssistant.TeacherFixtures.publish_trimester(ctx.scope, ctx.cg, term)

      {:ok, view, _} = live(conn_for(ctx.school, ctx.teacher), ~p"/school/courses")

      assert has_element?(
               view,
               "#bulletin-steps li[data-state=done]",
               "Publication des bulletins"
             )
    end

    test "a course row links to its statistics", ctx do
      {:ok, view, _} = live(conn_for(ctx.school, ctx.teacher), ~p"/school/courses")

      assert view |> element("#course-stats-#{ctx.tc.id}") |> render() =~
               "/school/statistics/me?period=seq%3A"
    end

    test "without the notes module there is no timeline and no Stats link", ctx do
      op = %TeacherAssistant.Scope{
        current_user: TeacherAssistant.TeacherFixtures.admin_user_fixture()
      }

      {:ok, _} = Organization.set_modules(op, ctx.school, [:appel])

      {:ok, view, _} = live(conn_for(ctx.school, ctx.teacher), ~p"/school/courses")
      assert has_element?(view, "#course-#{ctx.tc.id}")
      refute has_element?(view, "#bulletin-timeline")
      refute has_element?(view, "#course-stats-#{ctx.tc.id}")
    end
  end
end
