defmodule TeacherAssistantWeb.School.SanctionsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Discipline, Enrollment, Organization}
  alias TeacherAssistant.TeacherFixtures

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    [cg_a, cg_b | _] = Enrollment.list_class_groups(scope, year)
    {:ok, awa} = Enrollment.add_student(scope, cg_a, %{full_name: "Awa Nkolo", sex: :f})
    {:ok, _} = Enrollment.add_student(scope, cg_b, %{full_name: "Bob Eyong", sex: :m})
    [%{enrollment: awa_e}] = Enrollment.list_roster(scope, cg_a)
    [%{enrollment: bob_e}] = Enrollment.list_roster(scope, cg_b)

    {:ok, _} =
      Enrollment.add_guardian(scope, awa, %{
        full_name: "Jean Nkolo",
        relationship: :pere,
        phone: "677123456"
      })

    {:ok, s1} =
      Discipline.add_sanction(scope, awa_e, %{
        type: :blame,
        date: ~D[2025-09-12],
        reason: "Insolence"
      })

    {:ok, _} = Discipline.add_sanction(scope, bob_e, %{type: :consigne, date: ~D[2025-09-11]})
    %{cg_a: cg_a, awa_e: awa_e, s1: s1}
  end

  test "lists the year's sanctions and filters them", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sanctions")
    rows = view |> element("#sanction-rows") |> render()
    assert rows =~ "Awa Nkolo" and rows =~ "Bob Eyong"
    assert rows =~ "À notifier"

    {:ok, view, _} = live(conn, ~p"/school/sanctions?class=#{ctx.cg_a.id}")
    refute view |> element("#sanction-rows") |> render() =~ "Bob Eyong"

    {:ok, view, _} = live(conn, ~p"/school/sanctions?type=consigne")
    refute view |> element("#sanction-rows") |> render() =~ "Awa Nkolo"
  end

  test "the panel shows the guardian; notifying removes the row from « À notifier »",
       %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sanctions?notify=1&class=#{ctx.cg_a.id}")
    view |> element("#sanction-#{ctx.s1.id}") |> render_click()

    panel = view |> element("#sanction-panel") |> render()
    assert panel =~ "Jean Nkolo"
    assert panel =~ "tel:677123456"
    assert panel =~ "Insolence"

    view |> element("#notify-#{ctx.s1.id}") |> render_click()
    refute has_element?(view, "#sanction-#{ctx.s1.id}")
    assert Discipline.count_parents_to_notify(ctx.scope, ctx.year) == 1
  end

  test "quick entry: search a student, pick a type in use, save", %{conn: conn} = ctx do
    {:ok, view, _} = live(conn, ~p"/school/sanctions")

    view |> form("#student-search", %{"q" => "awa"}) |> render_change()
    view |> element("#pick-#{ctx.awa_e.id}") |> render_click()
    view |> element("#type-avertissement") |> render_click()

    view
    |> form("#sanction-entry", %{"entry" => %{"reason" => "Retards", "date" => "2025-09-15"}})
    |> render_submit()

    assert Discipline.list_school_sanctions(ctx.scope, ctx.year, type: :avertissement).count == 1
  end

  test "types switched off are not offered", %{conn: conn, scope: scope} do
    {:ok, profile} = TeacherAssistant.Accounts.fetch_school_profile(scope)

    {:ok, _} =
      profile
      |> Ash.Changeset.for_update(:update_school_life, %{sanction_types_in_use: [:blame]},
        scope: scope
      )
      |> Ash.update()

    {:ok, view, _} = live(conn, ~p"/school/sanctions")
    assert has_element?(view, "#type-blame")
    refute has_element?(view, "#type-consigne")
  end

  test "a plain teacher is sent back", %{workspace: ws, scope: scope} do
    teacher = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, teacher.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, ws.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/sanctions")
  end

  test "past 50 sanctions, a second page is reachable", %{conn: conn, scope: scope, awa_e: awa_e} do
    for day <- 1..50,
        do:
          {:ok, _} =
            Discipline.add_sanction(scope, awa_e, %{
              type: :consigne,
              date: Date.add(~D[2025-01-01], day)
            })

    {:ok, view, _} = live(conn, ~p"/school/sanctions")
    assert has_element?(view, "#sanctions-pager a", "2")

    # 52 sanctions, newest first: the oldest (2 Jan 2025) is on page 2 only.
    refute view |> element("#sanction-rows") |> render() =~ "02/01/2025"
    {:ok, view, _} = live(conn, ~p"/school/sanctions?page=2")
    assert view |> element("#sanction-rows") |> render() =~ "02/01/2025"
  end

  test "the menu badge follows « Marquer les parents notifiés »",
       %{workspace: ws, scope: scope} = ctx do
    sg = TeacherFixtures.member_scope_fixture(scope, %{roles: [:discipline_master]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, sg.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, ws.id)

    {:ok, view, _} = live(conn, ~p"/school/sanctions")
    assert view |> element("#nav-school-sanctions .badge") |> render() =~ "2"

    view |> element("#sanction-#{ctx.s1.id}") |> render_click()
    view |> element("#notify-#{ctx.s1.id}") |> render_click()
    assert view |> element("#nav-school-sanctions .badge") |> render() =~ "1"
  end
end
