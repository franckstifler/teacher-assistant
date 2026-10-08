defmodule TeacherAssistantWeb.School.ClassLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Accounts
  alias TeacherAssistant.Organization

  setup :register_and_log_in_user

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

  test "shows the roster with status and repeater", %{conn: conn, cg: cg, scope: scope} do
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f, repeater: true})
    {:ok, view, html} = live(conn, ~p"/school/classes/#{cg.id}")
    assert html =~ "Awa"
    # The sex in words, not the stored code.
    assert view |> element("tr", "Awa") |> render() =~ "Féminin"
  end

  test "enrolls a new student (inscription)", %{conn: conn, cg: cg, scope: scope} do
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> form("#enroll-form", %{
      "student" => %{"full_name" => "Bi", "sex" => "m", "matricule" => "M-3"}
    })
    |> render_submit()

    assert [%{student: %{full_name: "Bi"}}] = Enrollment.list_roster(scope, cg)
  end

  test "duplicate matricule surfaces a friendly error", %{conn: conn, cg: cg, scope: scope} do
    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f, matricule: "M-1"})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> form("#enroll-form", %{
      "student" => %{"full_name" => "Bi", "sex" => "m", "matricule" => "M-1"}
    })
    |> render_submit()

    assert length(Enrollment.list_roster(scope, cg)) == 1
    assert render(view) =~ "matricule"
  end

  test "search finds an existing student and re-enrolls (réinscription)", ctx do
    %{conn: conn, cg: cg, cg2: cg2, scope: scope} = ctx

    {:ok, %{student: s, enrollment: e}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Awa Zang", sex: :f, matricule: "M-1"})

    :ok = Enrollment.withdraw(scope, e)

    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg2.id}")
    view |> element("#enroll-search") |> render_change(%{"q" => "M-1"})
    assert render(view) =~ "Awa Zang"
    view |> element("#search-enroll-#{s.id}") |> render_click()

    assert [%{enrollment: %{status: :reinscription}}] = Enrollment.list_roster(scope, cg2)
  end

  test "transfer moves a student to another class", ctx do
    %{conn: conn, cg: cg, cg2: cg2, scope: scope} = ctx
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")

    view
    |> element("#transfer-#{e.id}")
    |> render_change(%{"class_group_id" => cg2.id})

    assert [] = Enrollment.list_roster(scope, cg)
    assert [_] = Enrollment.list_roster(scope, cg2)
  end

  test "withdraw removes the enrollment", %{conn: conn, cg: cg, scope: scope} do
    {:ok, %{enrollment: e}} = Enrollment.enroll_new(scope, cg, %{full_name: "Awa", sex: :f})
    {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
    view |> element("#withdraw-#{e.id}") |> render_click()
    assert [] = Enrollment.list_roster(scope, cg)
  end

  test "cross-school class id is not found", %{conn: conn, actor: user} do
    other_head = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, other_school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: other_head}, %{
        name: "Autre"
      })

    other_scope = school_scope(other_head, other_school)

    {:ok, oy} =
      Organization.create_academic_year(other_scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, ocg} =
      Enrollment.create_class_group(other_scope, oy, %{label: "6e Z", level: "6ème"})

    _ = user

    assert {:error, {:live_redirect, %{to: "/school/classes"}}} =
             live(conn, ~p"/school/classes/#{ocg.id}")
  end

  test "non-admin non-form-master member is redirected", ctx do
    %{school: school, cg: cg, user: head} = ctx
    other = TeacherAssistant.TeacherFixtures.user_fixture()

    {:ok, inv} =
      Accounts.invite_member(school_scope(head, school), %{
        email: to_string(other.email),
        roles: [:teacher]
      })

    {:ok, _} = Accounts.accept_invitation(%TeacherAssistant.Scope{current_user: other}, inv.token)

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
        |> Plug.Conn.put_session(:user_id, fm.id)
        |> Plug.Conn.put_session(:workspace_id, school.id)

      %{fm_conn: conn, fm: fm}
    end

    test "form master reaches the class and can enroll", %{fm_conn: conn, cg: cg, scope: scope} do
      {:ok, view, _} = live(conn, ~p"/school/classes/#{cg.id}")
      assert has_element?(view, "#enroll-form")

      view
      |> form("#enroll-form", %{"student" => %{"full_name" => "Zoe", "sex" => "f"}})
      |> render_submit()

      assert Enum.any?(Enrollment.list_roster(scope, cg), &(&1.student.full_name == "Zoe"))
    end

    test "a form master of another class is redirected", ctx do
      %{cg2: cg2, fm_conn: conn} = ctx
      # fm is form master of cg, not cg2
      assert {:error, {:live_redirect, %{to: "/school"}}} =
               live(conn, ~p"/school/classes/#{cg2.id}")
    end
  end
end
