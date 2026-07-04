defmodule TeacherAssistantWeb.School.ClassLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Academics
  alias TeacherAssistant.Academics.Enrollments
  alias TeacherAssistant.Accounts.Schools

  setup :register_and_log_in_user

  setup %{conn: conn, actor: user} do
    {:ok, school} = Schools.create_school(user, %{name: "Lycée D"})

    {:ok, year} =
      Academics.create_academic_year(school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, cg} = Academics.create_class_group(school, year, %{label: "6e A", level: "6ème"})
    {:ok, cg2} = Academics.create_class_group(school, year, %{label: "6e B", level: "6ème"})
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, year: year, cg: cg, cg2: cg2, user: user}
  end

  test "shows the roster with status and repeater", %{conn: conn, cg: cg} do
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f, repeater: true})
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

    assert [%{student: %{full_name: "Bi"}}] = Academics.list_roster(cg)
  end

  test "duplicate matricule surfaces a friendly error", %{conn: conn, cg: cg} do
    {:ok, _} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> form("#enroll-form", %{
      "student" => %{"full_name" => "Bi", "sex" => "m", "matricule" => "M-1"}
    })
    |> render_submit()

    assert length(Academics.list_roster(cg)) == 1
    assert render(view) =~ "matricule"
  end

  test "search finds an existing student and re-enrolls (réinscription)", ctx do
    %{conn: conn, cg: cg, cg2: cg2} = ctx

    {:ok, %{student: s, enrollment: e}} =
      Enrollments.enroll_new(cg, %{full_name: "Awa Zang", sex: :f, matricule: "M-1"})

    :ok = Enrollments.withdraw(e)

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}")
    view |> element("#enroll-search") |> render_change(%{"q" => "M-1"})
    assert render(view) =~ "Awa Zang"
    view |> element("#search-enroll-#{s.id}") |> render_click()

    assert [%{enrollment: %{status: :reinscription}}] = Academics.list_roster(cg2)
  end

  test "transfer moves a student to another class", ctx do
    %{conn: conn, cg: cg, cg2: cg2} = ctx
    {:ok, %{enrollment: e}} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> element("#transfer-#{e.id}")
    |> render_change(%{"class_group_id" => cg2.id})

    assert [] = Academics.list_roster(cg)
    assert [_] = Academics.list_roster(cg2)
  end

  test "withdraw removes the enrollment", %{conn: conn, cg: cg} do
    {:ok, %{enrollment: e}} = Enrollments.enroll_new(cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#withdraw-#{e.id}") |> render_click()
    assert [] = Academics.list_roster(cg)
  end

  test "cross-school class id is not found", %{conn: conn, actor: user} do
    other_head = TeacherAssistant.TeacherFixtures.user_fixture()
    {:ok, other_school} = Schools.create_school(other_head, %{name: "Autre"})

    {:ok, oy} =
      Academics.create_academic_year(other_school, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} = Academics.create_class_group(other_school, oy, %{label: "6e Z", level: "6ème"})
    _ = user

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}")
  end

  test "non-admin member: no mutation controls, forged events rejected", ctx do
    %{school: school, cg: cg, user: head} = ctx
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Schools.invite_member(school, head, %{email: to_string(other.email), roles: [:teacher]})

    {:ok, _} = Schools.accept_invitation(inv.token, other)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    refute has_element?(view, "#enroll-form")

    render_hook(view, "enroll_new", %{"student" => %{"full_name" => "X", "sex" => "m"}})
    assert [] = Academics.list_roster(cg)
  end

  describe "assignments panel" do
    test "assigns a teacher to a subject", %{conn: conn, cg: cg, user: head} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> form("#assign-form", %{
        "assignment" => %{"user_id" => head.id, "subject" => "Maths", "weekly_hours" => "5"}
      })
      |> render_submit()

      assert [tc] = TeacherAssistant.Academics.Assignments.list_for_class(cg)
      assert tc.subject == "Maths" and tc.teacher_user_id == head.id
    end

    test "duplicate subject on the class is rejected with a message", ctx do
      %{conn: conn, cg: cg, user: head} = ctx
      {:ok, _} = TeacherAssistant.Academics.Assignments.assign(cg, head, %{subject: "Maths"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view
      |> form("#assign-form", %{
        "assignment" => %{"user_id" => head.id, "subject" => "Maths", "weekly_hours" => "4"}
      })
      |> render_submit()

      assert length(TeacherAssistant.Academics.Assignments.list_for_class(cg)) == 1
      assert render(view) =~ "Maths"
    end

    test "unassign removes a data-free assignment; blocked with data", ctx do
      %{conn: conn, cg: cg, user: head} = ctx
      {:ok, tc} = TeacherAssistant.Academics.Assignments.assign(cg, head, %{subject: "Maths"})
      {:ok, _} = TeacherAssistant.Academics.create_progression_plan(tc, %{title: "P"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

      view |> element("#unassign-#{tc.id}") |> render_click()
      assert [_] = TeacherAssistant.Academics.Assignments.list_for_class(cg)

      {:ok, tc2} = TeacherAssistant.Academics.Assignments.assign(cg, head, %{subject: "Anglais"})
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      view |> element("#unassign-#{tc2.id}") |> render_click()
      assert length(TeacherAssistant.Academics.Assignments.list_for_class(cg)) == 1
    end
  end
end
