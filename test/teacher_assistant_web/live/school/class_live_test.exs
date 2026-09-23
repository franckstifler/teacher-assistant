defmodule TeacherAssistantWeb.School.ClassLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Organization.create_school(user, %{name: "Lycée D"})

    {:ok, year} =
      Organization.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, cg2} = Enrollment.create_class_group(school, year, %{label: "6e B", level: "6ème"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, cg2: cg2, user: user}
  end

  test "shows the roster with status and repeater", %{conn: conn, cg: cg} do
    {:ok, _} = Enrollment.enroll_new(cg, %{full_name: "Awa", sex: :f, repeater: true})
    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}")
    assert html =~ "Awa"
  end

  test "enrolls a new student (inscription)", %{conn: conn, cg: cg} do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> form("#enroll-form", %{
      "student" => %{"full_name" => "Bi", "sex" => "m", "matricule" => "M-3"}
    })
    |> render_submit()

    assert [%{student: %{full_name: "Bi"}}] = Enrollment.list_roster(cg)
  end

  test "duplicate matricule surfaces a friendly error", %{conn: conn, cg: cg} do
    {:ok, _} = Enrollment.enroll_new(cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> form("#enroll-form", %{
      "student" => %{"full_name" => "Bi", "sex" => "m", "matricule" => "M-1"}
    })
    |> render_submit()

    assert length(Enrollment.list_roster(cg)) == 1
    assert render(view) =~ "matricule"
  end

  test "search finds an existing student and re-enrolls (réinscription)", ctx do
    %{conn: conn, cg: cg, cg2: cg2} = ctx

    {:ok, %{student: s, enrollment: e}} =
      Enrollment.enroll_new(cg, %{full_name: "Awa Zang", sex: :f, matricule: "M-1"})

    :ok = Enrollment.withdraw(e)

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}")
    view |> element("#enroll-search") |> render_change(%{"q" => "M-1"})
    assert render(view) =~ "Awa Zang"
    view |> element("#search-enroll-#{s.id}") |> render_click()

    assert [%{enrollment: %{status: :reinscription}}] = Enrollment.list_roster(cg2)
  end

  test "transfer moves a student to another class", ctx do
    %{conn: conn, cg: cg, cg2: cg2} = ctx
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> element("#transfer-#{e.id}")
    |> render_change(%{"class_group_id" => cg2.id})

    assert [] = Enrollment.list_roster(cg)
    assert [_] = Enrollment.list_roster(cg2)
  end

  test "withdraw removes the enrollment", %{conn: conn, cg: cg} do
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#withdraw-#{e.id}") |> render_click()
    assert [] = Enrollment.list_roster(cg)
  end

  test "cross-school class id is not found", %{conn: conn, actor: user} do
    other_head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, other_school} = Organization.create_school(other_head, %{name: "Autre"})

    {:ok, oy} =
      Organization.create_academic_year(other_school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} = Enrollment.create_class_group(other_school, oy, %{label: "6e Z", level: "6ème"})
    _ = user

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}")
  end

  test "non-admin non-form-master member is redirected", ctx do
    %{school: school, cg: cg, user: head} = ctx
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Accounts.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}")
  end

  test "the class page has no fees link (fees deferred)", %{conn: conn, cg: cg} do
    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}")
    refute has_element?(view, "#go-to-fees")
  end

  describe "assignments panel" do
    test "assign form lists catalog subjects", %{conn: conn, school: school, cg: cg} do
      # "Musique" is not part of the school's seeded starter catalog, so
      # creating it here (rather than reusing a seeded subject) proves the
      # assign form reads live from the catalog.
      {:ok, _} =
        TeacherAssistant.Curriculum.create_subject(school, %{
          name: "Musique",
          default_coefficient: Decimal.new(4)
        })

      {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}")
      assert html =~ "Musique"
      assert html =~ "name=\"assignment[subject]\""
    end

    test "assigns a teacher to a subject", %{conn: conn, cg: cg, user: head} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> form("#assign-form", %{
        "assignment" => %{
          "user_id" => head.id,
          "subject" => "Mathématiques",
          "weekly_hours" => "5"
        }
      })
      |> render_submit()

      assert [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(cg)
      assert tc.subject == "Mathématiques" and tc.teacher_user_id == head.id
    end

    test "duplicate subject on the class is rejected with a message", ctx do
      %{conn: conn, cg: cg, user: head} = ctx

      {:ok, _} =
        TeacherAssistant.Curriculum.assign_teacher(cg, head, %{subject: "Mathématiques"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> form("#assign-form", %{
        "assignment" => %{
          "user_id" => head.id,
          "subject" => "Mathématiques",
          "weekly_hours" => "4"
        }
      })
      |> render_submit()

      assert length(TeacherAssistant.Curriculum.list_assignments_for_class(cg)) == 1
      assert render(view) =~ "Mathématiques"
    end

    test "unassign removes a data-free assignment; blocked with data", ctx do
      %{conn: conn, cg: cg, user: head} = ctx
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(cg, head, %{subject: "Maths"})
      {:ok, _} = TeacherAssistant.Curriculum.create_progression_plan(tc, %{title: "P"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view |> element("#unassign-#{tc.id}") |> render_click()
      assert [_] = TeacherAssistant.Curriculum.list_assignments_for_class(cg)

      {:ok, tc2} = TeacherAssistant.Curriculum.assign_teacher(cg, head, %{subject: "Anglais"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      view |> element("#unassign-#{tc2.id}") |> render_click()
      assert length(TeacherAssistant.Curriculum.list_assignments_for_class(cg)) == 1
    end

    test "assign defaults the coefficient from the chosen subject's catalog entry", %{
      conn: conn,
      cg: cg,
      user: head
    } do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> form("#assign-form", %{
        "assignment" => %{
          "user_id" => head.id,
          "subject" => "Mathématiques",
          "weekly_hours" => "4"
        }
      })
      |> render_submit()

      # "Mathématiques" is seeded with default_coefficient 4 (SchoolTemplates).
      [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(cg)
      assert Decimal.equal?(tc.coefficient, Decimal.new(4))
    end

    test "editing a coefficient inline persists it", %{conn: conn, cg: cg, user: head} do
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(cg, head, %{subject: "Maths"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> element("#coefficient-#{tc.id}")
      |> render_change(%{"coefficient" => "3"})

      [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(cg)
      assert Decimal.equal?(tc.coefficient, Decimal.new(3))
    end

    test "a non-admin non-form-master cannot reach the class to change a coefficient", ctx do
      %{school: school, cg: cg, user: head} = ctx
      {:ok, _tc} = TeacherAssistant.Curriculum.assign_teacher(cg, head, %{subject: "Maths"})
      other = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, inv} =
        TeacherAssistant.Accounts.invite_member(school, head, %{
          email: to_string(other.email),
          roles: [:teacher]
        })

      {:ok, _} = TeacherAssistant.Accounts.accept_invitation(inv.token, other)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:user_id, other.id)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      assert {:error, {:live_redirect, %{to: "/school"}}} =
               live(conn, ~p"/school/classes/#{cg.id}")
    end
  end

  describe "teach together / split (combined courses)" do
    test "admin combines this class with a sibling class", %{
      conn: conn,
      cg: cg,
      cg2: cg2,
      user: head
    } do
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(cg, head, %{subject: "Maths"})
      {:ok, tc2} = TeacherAssistant.Curriculum.assign_teacher(cg2, head, %{subject: "Maths"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> element("#teach-together-#{tc.id}")
      |> render_submit(%{"sibling-ids" => [tc2.id]})

      {:ok, reloaded_tc} = TeacherAssistant.Curriculum.get_teaching_context(tc.id)
      {:ok, reloaded_tc2} = TeacherAssistant.Curriculum.get_teaching_context(tc2.id)

      assert reloaded_tc.combined_course_id
      assert reloaded_tc.combined_course_id == reloaded_tc2.combined_course_id
    end

    test "combined row shows the real class labels (not the bare level) and a split control", %{
      conn: conn,
      cg: cg,
      cg2: cg2,
      user: head
    } do
      # cg is "6e A" and cg2 is "6e B" — same level ("6ème"), distinct class
      # labels. The initiating context (cg) arrives here from
      # Curriculum.list_assignments_for_class/1, which does NOT preload :class_group —
      # this pins that Curriculum.combine_course/1 loads it itself rather than
      # collapsing to a degenerate "Maths · 6ème" label.
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(cg, head, %{subject: "Maths"})
      {:ok, tc2} = TeacherAssistant.Curriculum.assign_teacher(cg2, head, %{subject: "Maths"})
      {:ok, course} = TeacherAssistant.Curriculum.combine_course([tc, tc2])

      assert course.label == "Maths · 6e A+6e B"

      {:ok, view, html} = live(conn, ~p"/school/classes/#{cg.id}")
      assert html =~ "Maths · 6e A+6e B"
      assert has_element?(view, "#split-#{tc.id}")
    end

    test "split unlinks a combined assignment", %{
      conn: conn,
      cg: cg,
      cg2: cg2,
      user: head
    } do
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(cg, head, %{subject: "Maths"})
      {:ok, tc2} = TeacherAssistant.Curriculum.assign_teacher(cg2, head, %{subject: "Maths"})
      {:ok, _course} = TeacherAssistant.Curriculum.combine_course([tc, tc2])

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      view |> element("#split-#{tc.id}") |> render_click()

      {:ok, reloaded_tc} = TeacherAssistant.Curriculum.get_teaching_context(tc.id)
      {:ok, reloaded_tc2} = TeacherAssistant.Curriculum.get_teaching_context(tc2.id)
      assert reloaded_tc.combined_course_id == nil
      assert reloaded_tc2.combined_course_id == nil
    end

    test "a mismatched combine (different subject) surfaces a friendly flash", %{
      conn: conn,
      cg: cg,
      cg2: cg2,
      user: head
    } do
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(cg, head, %{subject: "Maths"})

      {:ok, _other_subject_tc} =
        TeacherAssistant.Curriculum.assign_teacher(cg2, head, %{subject: "Anglais"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      # No eligible sibling for "Maths" exists, so the control is not shown at all.
      refute has_element?(view, "#teach-together-#{tc.id}")
    end
  end

  describe "form master" do
    test "admin assigns then clears the form master", %{
      conn: conn,
      cg: cg,
      school: school,
      user: head
    } do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> element("#form-master-form")
      |> render_change(%{"user_id" => head.id})

      assert TeacherAssistant.Enrollment.fetch_owned_class_group(cg.id, school)
             |> elem(1)
             |> Map.get(:form_master_user_id) == head.id

      view |> element("#form-master-form") |> render_change(%{"user_id" => ""})

      assert TeacherAssistant.Enrollment.fetch_owned_class_group(cg.id, school)
             |> elem(1)
             |> Map.get(:form_master_user_id) == nil
    end

    test "a non-admin cannot set the form master (forged event)", ctx do
      %{school: school, cg: cg, user: head} = ctx
      other = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, inv} =
        Accounts.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

      {:ok, _} = Accounts.accept_invitation(inv.token, other)
      {:ok, _} = TeacherAssistant.Enrollment.set_form_master(cg, other.id)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:user_id, other.id)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      render_hook(view, "set_form_master", %{"user_id" => head.id})

      assert TeacherAssistant.Enrollment.fetch_owned_class_group(cg.id, school)
             |> elem(1)
             |> Map.get(:form_master_user_id) == other.id
    end
  end

  describe "form master access" do
    setup ctx do
      %{school: school, cg: cg, user: head} = ctx
      fm = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, inv} =
        Accounts.invite_member(school, head, %{email: to_string(fm.email), roles: [:teacher]})

      {:ok, _} = Accounts.accept_invitation(inv.token, fm)
      {:ok, _} = TeacherAssistant.Enrollment.set_form_master(cg, fm.id)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> Plug.Conn.put_session(:user_id, fm.id)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      %{fm_conn: conn, fm: fm}
    end

    test "form master reaches the class and can enroll", %{fm_conn: conn, cg: cg} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      assert has_element?(view, "#enroll-form")

      view
      |> form("#enroll-form", %{"student" => %{"full_name" => "Zoe", "sex" => "f"}})
      |> render_submit()

      assert Enum.any?(Enrollment.list_roster(cg), &(&1.student.full_name == "Zoe"))
    end

    test "form master sees no assignments/form-master controls", %{fm_conn: conn, cg: cg} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      refute has_element?(view, "#assign-form")
      refute has_element?(view, "#form-master-form")
    end

    test "form master cannot assign a teacher (forged event)", %{fm_conn: conn, cg: cg, fm: fm} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      render_hook(view, "assign", %{"assignment" => %{"user_id" => fm.id, "subject" => "X"}})
      assert TeacherAssistant.Curriculum.list_assignments_for_class(cg) == []
    end

    test "form master cannot change a coefficient (forged event)", %{
      fm_conn: conn,
      cg: cg,
      user: head
    } do
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(cg, head, %{subject: "Maths"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      render_hook(view, "set_coefficient", %{"context-id" => tc.id, "coefficient" => "9"})
      [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(cg)
      assert Decimal.equal?(tc.coefficient, Decimal.new(1))
    end

    test "form master cannot set the form master (forged event)", %{
      fm_conn: conn,
      cg: cg,
      fm: fm,
      user: head,
      school: school
    } do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      render_hook(view, "set_form_master", %{"user_id" => head.id})
      {:ok, reloaded} = TeacherAssistant.Enrollment.fetch_owned_class_group(cg.id, school)
      assert reloaded.form_master_user_id == fm.id
    end

    test "form master cannot combine classes (forged teach_together)", %{
      fm_conn: conn,
      cg: cg,
      cg2: cg2,
      user: head
    } do
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(cg, head, %{subject: "Maths"})
      {:ok, tc2} = TeacherAssistant.Curriculum.assign_teacher(cg2, head, %{subject: "Maths"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      render_hook(view, "teach_together", %{"context-id" => tc.id, "sibling-ids" => [tc2.id]})

      {:ok, reloaded_tc} = TeacherAssistant.Curriculum.get_teaching_context(tc.id)
      assert reloaded_tc.combined_course_id == nil
    end

    test "form master cannot split a combined course (forged split_course)", %{
      fm_conn: conn,
      cg: cg,
      cg2: cg2,
      user: head
    } do
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(cg, head, %{subject: "Maths"})
      {:ok, tc2} = TeacherAssistant.Curriculum.assign_teacher(cg2, head, %{subject: "Maths"})
      {:ok, _course} = TeacherAssistant.Curriculum.combine_course([tc, tc2])

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      render_hook(view, "split_course", %{"context-id" => tc.id})

      {:ok, reloaded_tc} = TeacherAssistant.Curriculum.get_teaching_context(tc.id)
      assert reloaded_tc.combined_course_id != nil
    end

    test "a form master of another class is redirected", ctx do
      %{school: school, cg2: cg2, fm_conn: conn} = ctx
      # fm is form master of cg, not cg2
      assert {:error, {:live_redirect, %{to: "/school"}}} =
               live(conn, ~p"/school/classes/#{cg2.id}")
    end
  end
end
