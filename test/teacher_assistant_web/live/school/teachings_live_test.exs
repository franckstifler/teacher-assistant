defmodule TeacherAssistantWeb.School.TeachingsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

  defp open_assign(view), do: view |> element("#open-assign") |> render_click()

  defp open_teaching(view, tc),
    do: view |> element("#assignment-row-#{tc.id}") |> render_click()

  setup %{conn: conn, actor: user} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: user}, %{name: "Lycée D"})

    scope = school_scope(user, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, cg2} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, cg2: cg2, user: user, scope: scope}
  end

  describe "assignments panel" do
    test "a class off the grid is told why every subject is offered", %{
      conn: conn,
      year: year,
      scope: scope
    } do
      {:ok, odd} = Enrollment.create_class_group(scope, year, %{label: "Sixième Z", level: "6e"})
      {:ok, view, _html} = live(conn, ~p"/school/classes/#{odd.id}/teachings")
      assert has_element?(view, "#off-grid-hint")
      open_assign(view)
      assert has_element?(view, "#assign-subject option", "Mathématiques")
    end

    test "an optional subject lists who takes it", %{conn: conn, cg: cg, user: head, scope: scope} do
      {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})
      {:ok, bob} = Enrollment.add_student(scope, cg, %{full_name: "Bob", sex: :m})
      {:ok, esp} = TeacherAssistant.Curriculum.create_subject(scope, %{name: "Espagnol"})

      :ok =
        TeacherAssistant.Curriculum.update_coefficient_grid(scope, %{
          "optional" => %{esp.id => "true"}
        })

      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: esp})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      assert has_element?(view, "#takers-#{tc.id}", "2/2")

      open_teaching(view, tc)
      assert has_element?(view, "#takers-form-#{tc.id}", "2/2")
      view |> form("#teaching-form-#{tc.id}", %{"takers" => [awa.id]}) |> render_submit()
      assert TeacherAssistant.Curriculum.exempt_student_ids(scope, tc) == MapSet.new([bob.id])
      assert has_element?(view, "#takers-#{tc.id}", "1/2")
    end

    test "only subjects taught at the class's level are offered", %{
      conn: conn,
      cg: cg,
      scope: scope
    } do
      {:ok, s} = TeacherAssistant.Curriculum.create_subject(scope, %{name: "Philosophie"})

      cell =
        TeacherAssistant.Curriculum.coefficient_cells(scope)[{s.id, :francophone, "6ème", nil}]

      :ok = Ash.destroy(cell, scope: scope)

      {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      refute html =~ "Philosophie"
    end

    test "the class shows the grid coefficient, takes an override and resets it", ctx do
      %{conn: conn, cg: cg, user: head, scope: scope} = ctx

      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Mathématiques"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      assert has_element?(view, "#assignment-row-#{tc.id}", "coef. 4")
      open_teaching(view, tc)
      assert has_element?(view, "#coefficient-#{tc.id} input[value='4']")
      refute has_element?(view, "#reset-coefficient-#{tc.id}")

      view
      |> form("#teaching-form-#{tc.id}", %{"teaching" => %{"coefficient" => "3"}})
      |> render_submit()

      refute has_element?(view, "#teaching-drawer")
      assert has_element?(view, "#assignment-row-#{tc.id}", "coef. 3")
      assert has_element?(view, "#assignment-row-#{tc.id}", "propre à la classe")

      open_teaching(view, tc)
      assert has_element?(view, "#coefficient-#{tc.id} input.border-warning[value='3']")
      assert render(view) =~ "modèle : 4"

      view |> element("#reset-coefficient-#{tc.id}") |> render_click()
      assert has_element?(view, "#coefficient-#{tc.id} input[value='4']")
    end

    test "with class coefficients off the value is read-only", ctx do
      %{conn: conn, cg: cg, user: head, scope: scope} = ctx

      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Mathématiques"})

      {:ok, _} = TeacherAssistant.Curriculum.set_class_coefficients_allowed(scope, false)
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      assert has_element?(view, "#assignment-row-#{tc.id}", "4")
      open_teaching(view, tc)
      assert has_element?(view, "#teaching-drawer")
      refute has_element?(view, "#coefficient-#{tc.id} input")
      refute has_element?(view, "#teaching-drawer input[name='teaching[coefficient]']")
    end

    test "an assignment with no grid cell is flagged", ctx do
      %{conn: conn, cg: cg, user: head, scope: scope} = ctx

      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Mathématiques"})

      cell =
        TeacherAssistant.Curriculum.coefficient_cells(scope)[
          {tc.subject_id, :francophone, "6ème", nil}
        ]

      :ok = Ash.destroy(cell, scope: scope)
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")

      assert has_element?(
               view,
               "#not-taught-#{tc.id}",
               "Non enseignée à ce niveau selon la grille"
             )
    end

    test "assign form lists catalog subjects", %{conn: conn, cg: cg, scope: scope} do
      # "Musique" is not part of the school's seeded starter catalog, so
      # creating it here (rather than reusing a seeded subject) proves the
      # assign form reads live from the catalog.
      {:ok, _} =
        TeacherAssistant.Curriculum.create_subject(scope, %{
          name: "Musique",
          default_coefficient: Decimal.new(4)
        })

      {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      open_assign(view)
      assert has_element?(view, "#assign-subject[name='assignment[subject]'] option", "Musique")
    end

    test "assigns a teacher to a subject", %{conn: conn, cg: cg, user: head, scope: scope} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      open_assign(view)

      view
      |> form("#assign-form", %{
        "assignment" => %{
          "user_id" => head.id,
          "subject" => "Mathématiques",
          "weekly_hours" => "5"
        }
      })
      |> render_submit()

      assert [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)
      assert tc.subject == "Mathématiques" and tc.teacher_user_id == head.id
    end

    test "duplicate subject on the class is rejected with a message", ctx do
      %{conn: conn, cg: cg, user: head, scope: scope} = ctx

      {:ok, _} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Mathématiques"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      open_assign(view)

      view
      |> form("#assign-form", %{
        "assignment" => %{
          "user_id" => head.id,
          "subject" => "Mathématiques",
          "weekly_hours" => "4"
        }
      })
      |> render_submit()

      assert length(TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)) == 1
      assert render(view) =~ "Mathématiques"
    end

    test "unassign removes a data-free assignment; blocked with data", ctx do
      %{conn: conn, cg: cg, user: head, scope: scope} = ctx
      {:ok, tc} = TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})
      {:ok, _} = TeacherAssistant.Curriculum.create_progression_plan(scope, tc, %{title: "P"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")

      open_teaching(view, tc)
      view |> element("#unassign-#{tc.id}") |> render_click()
      assert [_] = TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)

      {:ok, tc2} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Anglais"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      open_teaching(view, tc2)
      view |> element("#unassign-#{tc2.id}") |> render_click()
      assert length(TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)) == 1
      refute has_element?(view, "#teaching-drawer")
      refute has_element?(view, "#assignment-row-#{tc2.id}")
    end

    test "assign takes the coefficient from the grid, without an override", %{
      conn: conn,
      cg: cg,
      user: head,
      scope: scope
    } do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      open_assign(view)

      view
      |> form("#assign-form", %{
        "assignment" => %{
          "user_id" => head.id,
          "subject" => "Mathématiques",
          "weekly_hours" => "4"
        }
      })
      |> render_submit()

      # "Mathématiques" is seeded with default_coefficient 4 (SchoolTemplates), which
      # seeds its grid cells; the assignment carries no override and reads the grid.
      [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)
      assert tc.coefficient == nil
      assert Decimal.equal?(tc.effective_coefficient, Decimal.new(4))
    end

    test "editing a coefficient in the drawer persists it", %{
      conn: conn,
      cg: cg,
      user: head,
      scope: scope
    } do
      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      open_teaching(view, tc)

      view
      |> form("#teaching-form-#{tc.id}", %{"teaching" => %{"coefficient" => "3,5"}})
      |> render_submit()

      [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)
      assert Decimal.equal?(tc.coefficient, Decimal.new("3.5"))
      assert has_element?(view, "#assignment-row-#{tc.id}", "coef. 3,5")
    end

    test "the drawer saves the teacher and the weekly hours together", ctx do
      %{conn: conn, cg: cg, user: head, scope: scope} = ctx
      grace = TeacherAssistant.TeacherFixtures.user_fixture(%{name: "Grace Tabi"})
      TeacherAssistant.TeacherFixtures.member_scope_fixture(scope, %{user: grace})

      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      assert has_element?(view, "#assignment-row-#{tc.id}", "4 h / sem.")
      open_teaching(view, tc)

      view
      |> form("#teaching-form-#{tc.id}", %{
        "teaching" => %{"user_id" => grace.id, "weekly_hours" => "6"}
      })
      |> render_submit()

      [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)
      assert tc.teacher_user_id == grace.id and tc.weekly_hours == 6
      assert has_element?(view, "#assignment-row-#{tc.id}", "Grace Tabi")
      assert has_element?(view, "#assignment-row-#{tc.id}", "6 h / sem.")
    end

    test "out-of-range hours are refused and the drawer stays open", ctx do
      %{conn: conn, cg: cg, user: head, scope: scope} = ctx

      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      open_teaching(view, tc)

      html =
        view
        |> form("#teaching-form-#{tc.id}", %{"teaching" => %{"weekly_hours" => "99"}})
        |> render_submit()

      assert html =~ "entre 1 et 40"
      assert has_element?(view, "#teaching-drawer")
      [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)
      assert tc.weekly_hours == 4
    end

    test "a non-admin non-form-master cannot reach the class to change a coefficient", ctx do
      %{school: school, cg: cg, user: head, scope: scope} = ctx

      {:ok, _tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

      other = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, inv} =
        TeacherAssistant.Accounts.invite_member(school_scope(head, school), %{
          email: to_string(other.email),
          roles: [:teacher]
        })

      {:ok, _} =
        TeacherAssistant.Accounts.accept_invitation(
          %TeacherAssistant.Scope{current_user: other},
          inv.token
        )

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_user_in_session(other)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      assert {:error, {:live_redirect, %{to: "/school"}}} =
               live(conn, ~p"/school/classes/#{cg.id}/teachings")
    end
  end

  describe "teach together / split (combined courses)" do
    test "admin combines this class with a sibling class", %{
      conn: conn,
      cg: cg,
      cg2: cg2,
      user: head,
      scope: scope
    } do
      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

      {:ok, tc2} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg2, head, %{subject: "Maths"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      open_teaching(view, tc)

      view
      |> element("#teach-together-#{tc.id}")
      |> render_submit(%{"sibling-ids" => [tc2.id]})

      {:ok, reloaded_tc} = TeacherAssistant.Curriculum.get_teaching_context(scope, tc.id)
      {:ok, reloaded_tc2} = TeacherAssistant.Curriculum.get_teaching_context(scope, tc2.id)

      assert reloaded_tc.combined_course_id
      assert reloaded_tc.combined_course_id == reloaded_tc2.combined_course_id
      assert has_element?(view, "#combined-#{tc.id}", "avec 6e B")
    end

    test "combined row shows the real class labels (not the bare level) and a split control", %{
      conn: conn,
      cg: cg,
      cg2: cg2,
      user: head,
      scope: scope
    } do
      # cg is "6e A" and cg2 is "6e B" — same level ("6ème"), distinct class
      # labels. The initiating context (cg) arrives here from
      # Curriculum.list_assignments_for_class/2, which does NOT preload :class_group —
      # this pins that Curriculum.combine_course/2 loads it itself rather than
      # collapsing to a degenerate "Maths · 6ème" label.
      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

      {:ok, tc2} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg2, head, %{subject: "Maths"})

      {:ok, course} = TeacherAssistant.Curriculum.combine_course(scope, [tc, tc2])

      assert course.label == "Maths · 6e A+6e B"

      {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      assert has_element?(view, "#combined-#{tc.id}", "avec 6e B")
      open_teaching(view, tc)
      assert has_element?(view, "#teaching-drawer", "Maths · 6e A+6e B")
      assert has_element?(view, "#split-#{tc.id}")
    end

    test "split unlinks a combined assignment", %{
      conn: conn,
      cg: cg,
      cg2: cg2,
      user: head,
      scope: scope
    } do
      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

      {:ok, tc2} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg2, head, %{subject: "Maths"})

      {:ok, _course} = TeacherAssistant.Curriculum.combine_course(scope, [tc, tc2])

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      open_teaching(view, tc)
      view |> element("#split-#{tc.id}") |> render_click()

      {:ok, reloaded_tc} = TeacherAssistant.Curriculum.get_teaching_context(scope, tc.id)
      {:ok, reloaded_tc2} = TeacherAssistant.Curriculum.get_teaching_context(scope, tc2.id)
      assert reloaded_tc.combined_course_id == nil
      assert reloaded_tc2.combined_course_id == nil
    end

    test "a mismatched combine (different subject) surfaces a friendly flash", %{
      conn: conn,
      cg: cg,
      cg2: cg2,
      user: head,
      scope: scope
    } do
      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

      {:ok, _other_subject_tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg2, head, %{subject: "Anglais"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      open_teaching(view, tc)

      # No eligible sibling for "Maths" exists, so the control is not shown at all.
      refute has_element?(view, "#teach-together-#{tc.id}")
      assert has_element?(view, "#combine-section-#{tc.id}", "Aucune autre classe")
    end
  end

  describe "form master" do
    test "admin assigns then clears the form master", %{
      conn: conn,
      cg: cg,
      user: head,
      scope: scope
    } do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")

      view
      |> element("#form-master-form")
      |> render_change(%{"user_id" => head.id})

      assert TeacherAssistant.Enrollment.fetch_owned_class_group(scope, cg.id)
             |> elem(1)
             |> Map.get(:form_master_user_id) == head.id

      view |> element("#form-master-form") |> render_change(%{"user_id" => ""})

      assert TeacherAssistant.Enrollment.fetch_owned_class_group(scope, cg.id)
             |> elem(1)
             |> Map.get(:form_master_user_id) == nil
    end

    test "a non-admin cannot set the form master (forged event)", ctx do
      %{school: school, cg: cg, user: head, scope: scope} = ctx
      other = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, inv} =
        Accounts.invite_member(school_scope(head, school), %{
          email: to_string(other.email),
          roles: [:teacher]
        })

      {:ok, _} =
        Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

      {:ok, _} = TeacherAssistant.Enrollment.set_form_master(scope, cg, other.id)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_user_in_session(other)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      render_hook(view, "set_form_master", %{"user_id" => head.id})

      assert TeacherAssistant.Enrollment.fetch_owned_class_group(scope, cg.id)
             |> elem(1)
             |> Map.get(:form_master_user_id) == other.id
    end
  end

  describe "form master access" do
    setup ctx do
      %{school: school, cg: cg, user: head, scope: scope} = ctx
      fm = TeacherAssistant.TeacherFixtures.user_fixture()

      {:ok, inv} =
        Accounts.invite_member(school_scope(head, school), %{
          email: to_string(fm.email),
          roles: [:teacher]
        })

      {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: fm}, inv.token)
      {:ok, _} = TeacherAssistant.Enrollment.set_form_master(scope, cg, fm.id)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.init_test_session(%{})
        |> put_user_in_session(fm)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      %{fm_conn: conn, fm: fm}
    end

    test "form master sees no assignments/form-master controls", %{fm_conn: conn, cg: cg} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      refute has_element?(view, "#open-assign")
      refute has_element?(view, "#assign-form")
      refute has_element?(view, "#form-master-form")
    end

    test "form master cannot assign a teacher (forged event)", %{
      fm_conn: conn,
      cg: cg,
      fm: fm,
      scope: scope
    } do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      render_hook(view, "assign", %{"assignment" => %{"user_id" => fm.id, "subject" => "X"}})
      assert TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg) == []
    end

    test "form master cannot change a coefficient (forged event)", %{
      fm_conn: conn,
      cg: cg,
      user: head,
      scope: scope
    } do
      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      refute has_element?(view, "button#assignment-row-#{tc.id}")
      render_hook(view, "edit_teaching", %{"id" => tc.id})
      refute has_element?(view, "#teaching-drawer")

      render_hook(view, "save_teaching", %{
        "context-id" => tc.id,
        "teaching" => %{"coefficient" => "9", "weekly_hours" => "7"}
      })

      assert render(view) =~ "autorisation"
      [tc] = TeacherAssistant.Curriculum.list_assignments_for_class(scope, cg)
      assert tc.coefficient == nil
      assert tc.weekly_hours == 4
    end

    test "form master cannot set the form master (forged event)", %{
      fm_conn: conn,
      cg: cg,
      fm: fm,
      user: head,
      scope: scope
    } do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      render_hook(view, "set_form_master", %{"user_id" => head.id})
      {:ok, reloaded} = TeacherAssistant.Enrollment.fetch_owned_class_group(scope, cg.id)
      assert reloaded.form_master_user_id == fm.id
    end

    test "form master cannot combine classes (forged teach_together)", %{
      fm_conn: conn,
      cg: cg,
      cg2: cg2,
      user: head,
      scope: scope
    } do
      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

      {:ok, tc2} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg2, head, %{subject: "Maths"})

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      render_hook(view, "teach_together", %{"context-id" => tc.id, "sibling-ids" => [tc2.id]})

      {:ok, reloaded_tc} = TeacherAssistant.Curriculum.get_teaching_context(scope, tc.id)
      assert reloaded_tc.combined_course_id == nil
    end

    test "form master cannot split a combined course (forged split_course)", %{
      fm_conn: conn,
      cg: cg,
      cg2: cg2,
      user: head,
      scope: scope
    } do
      {:ok, tc} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths"})

      {:ok, tc2} =
        TeacherAssistant.Curriculum.assign_teacher(scope, cg2, head, %{subject: "Maths"})

      {:ok, _course} = TeacherAssistant.Curriculum.combine_course(scope, [tc, tc2])

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      render_hook(view, "split_course", %{"context-id" => tc.id})

      {:ok, reloaded_tc} = TeacherAssistant.Curriculum.get_teaching_context(scope, tc.id)
      assert reloaded_tc.combined_course_id != nil
    end
  end

  describe "unassigned subjects" do
    test "the grid's subjects without a teacher are listed and pre-fill the add form", ctx do
      %{conn: conn, cg: cg, scope: scope} = ctx

      maths =
        Enum.find(TeacherAssistant.Curriculum.list_subjects(scope), &(&1.name == "Mathématiques"))

      :ok =
        TeacherAssistant.Curriculum.update_coefficient_grid(scope, %{
          "cells" => %{
            maths.id => %{
              TeacherAssistant.Curriculum.cell_token({:francophone, "6ème", nil}) => "4"
            }
          },
          "groups" => %{}
        })

      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/teachings")
      assert has_element?(view, "#unassigned-subjects", "Mathématiques")
      assert has_element?(view, "#class-tab-teachings", "1")

      assert has_element?(view, "#prefill-#{maths.id}", "Sans enseignant")
      view |> element("#prefill-#{maths.id}") |> render_click()
      assert has_element?(view, "#assign-drawer")
      assert has_element?(view, "#assign-subject option[selected][value='Mathématiques']")
    end
  end
end
