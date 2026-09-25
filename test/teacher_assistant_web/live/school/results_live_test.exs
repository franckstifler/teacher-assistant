defmodule TeacherAssistantWeb.School.ResultsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Assessment
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Curriculum
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization
  alias TeacherAssistant.Accounts.SchoolMembership, as: SchoolMembership

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    scope = %TeacherAssistant.Scope{current_user: head}
    {:ok, school} = Organization.create_school(scope, %{name: "Lycée R"})
    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    [seq | _] = Organization.list_sequences(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, _} = Enrollment.add_student(scope, cg, %{full_name: "Awa", sex: :f})

    {:ok, tc} =
      Curriculum.assign_teacher(scope, cg, head, %{subject: "Maths", coefficient: Decimal.new(4)})

    {:ok, a} =
      Assessment.create_assessment(scope, tc, seq, %{
        label: "D1",
        weight: Decimal.new(1),
        max_score: Decimal.new(20)
      })

    [student] = Enrollment.list_students(scope, cg)
    :ok = Assessment.upsert_marks(scope, a, [%{student_id: student.id, score: Decimal.new(15)}])
    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, school: school, cg: cg, seq: seq, student: student, head: head, scope: scope}
  end

  test "renders the ranked results with the moyenne générale", %{conn: conn, cg: cg} do
    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}/results")
    assert html =~ "Awa"
    assert html =~ "15"
  end

  test "cross-school class id redirects", %{conn: conn, head: head} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, os} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: other}, %{name: "Autre"})

    other_scope = school_scope(other, os)

    {:ok, oy} =
      Organization.create_academic_year(other_scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} = Enrollment.create_class_group(other_scope, oy, %{label: "6e Z", level: "6ème"})
    _ = head

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}/results")
  end

  test "a non-admin member is redirected to /school", %{school: school, cg: cg, scope: scope} do
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(scope, %{email: to_string(other.email), roles: [:teacher]})

    # Pre-create membership so school_scope works for acceptance
    {:ok, _m} =
      SchoolMembership
      |> Ash.Changeset.for_create(:create, %{
        user_id: other.id,
        roles: inv.roles,
        status: inv.membership_status
      })
      |> Ash.Changeset.set_tenant(school.id)
      |> Ash.create()

    {:ok, _} = Accounts.accept_invitation(school_scope(other, school), inv.token)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, other.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn, ~p"/school/classes/#{cg.id}/results")
  end

  test "the form master can view results for their class", %{
    cg: cg,
    school: school,
    scope: scope
  } do
    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(scope, %{email: to_string(fm.email), roles: [:teacher]})

    # Pre-create membership so school_scope works for acceptance
    {:ok, _m} =
      SchoolMembership
      |> Ash.Changeset.for_create(:create, %{
        user_id: fm.id,
        roles: inv.roles,
        status: inv.membership_status
      })
      |> Ash.Changeset.set_tenant(school.id)
      |> Ash.create()

    {:ok, _} = Accounts.accept_invitation(school_scope(fm, school), inv.token)
    {:ok, _} = Enrollment.set_form_master(scope, cg, fm.id)
    {:ok, _} = Enrollment.set_form_master(scope, cg, fm.id)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, fm.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}/results")
    assert html =~ "Awa"
  end

  test "the period selector switches to a trimester and recomputes", %{
    conn: conn,
    cg: cg,
    scope: scope
  } do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}/results")
    # séquence 1 is the default; switch to Trimestre 1
    year = TeacherAssistant.Organization.current_academic_year(scope)
    [term1 | _] = TeacherAssistant.Organization.list_terms(scope, year)

    html =
      view
      |> element("#results-period-form")
      |> render_change(%{"period" => "trim:#{term1.id}"})

    assert html =~ "Awa"

    assert render(view) =~ "period=trim%3A#{term1.id}" or
             render(view) =~ "period=trim:#{term1.id}"
  end

  test "results header shows the form master when set", %{
    conn: conn,
    cg: cg,
    school: school,
    scope: scope
  } do
    fm = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(scope, %{email: to_string(fm.email), roles: [:teacher]})

    # Pre-create membership so school_scope works for acceptance
    {:ok, _m} =
      SchoolMembership
      |> Ash.Changeset.for_create(:create, %{
        user_id: fm.id,
        roles: inv.roles,
        status: inv.membership_status
      })
      |> Ash.Changeset.set_tenant(school.id)
      |> Ash.create()

    {:ok, _} = Accounts.accept_invitation(school_scope(fm, school), inv.token)
    {:ok, _} = Enrollment.set_form_master(scope, cg, fm.id)

    {:ok, _view, html} = live(conn, ~p"/school/classes/#{cg.id}/results")
    assert html =~ to_string(fm.email)
    assert html =~ "Professeur principal"
  end
end
